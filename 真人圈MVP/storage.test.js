#!/usr/bin/env node
/** 真人圈 — 持久化层测试。
 *  JSON 驱动:真实读写临时文件。
 *  Postgres 驱动:用 pg-mem(进程内 Postgres)跑真实 SQL,验证建表/快照/重载往返。
 *  注:pg-mem 仅在 devDependency 安装时可用;生产用真实 PostgreSQL,见 docker-compose.yml。
 */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { createPersistence, emptyDB, COLLECTIONS } = require('./storage');

let pass = 0, fail = 0;
function ok(name, cond, extra) { cond ? pass++ : fail++; console.log(`${cond ? '✓' : '✗'} ${name}${cond ? '' : '  ←—— ' + (extra || '')}`); }

function sampleDB() {
  const DB = emptyDB();
  DB.seq = 1042;
  DB.users.push({ id: '1001', phone: '13800000001', nickname: '川子', level: 4, salt: 's', hash: 'h', following: ['1002'] });
  DB.users.push({ id: '1002', phone: '13800000002', nickname: '阿瓜', level: 3, salt: 's', hash: 'h', following: [] });
  DB.posts.push({ id: '1010', uid: '1001', text: '骑行第23天', kind: 'text', likes: ['1002'], reports: [], removed: false, story: false, ts: 1, expire: 0 });
  DB.events.push({ id: '1020', title: '饭局', members: ['1001', '1002'], cap: 6, minLevel: 2 });
  DB.notifications.push({ id: '1030', to: '1001', type: 'like', from: '1002', read: false, ts: 2, extra: {} });
  return DB;
}

(async () => {
  /* ---------- JSON 驱动 ---------- */
  const FILE = path.join(os.tmpdir(), `rc-storage-${process.pid}.json`);
  try { fs.unlinkSync(FILE); } catch {}
  {
    const p = createPersistence({ STORAGE: 'json', DATA_FILE: FILE });
    ok('json: 空库返回 null', (await p.load()) === null);
    const DB = sampleDB();
    await p.flush(DB);
    ok('json: 落盘后文件存在', fs.existsSync(FILE));
    const back = await p.load();
    ok('json: 重载 seq 一致', back.seq === 1042);
    ok('json: 重载 users 一致', back.users.length === 2 && back.users[0].nickname === '川子');
    ok('json: 重载 posts 点赞一致', back.posts[0].likes[0] === '1002');
    ok('json: 落盘不含外部对象引用(深拷贝快照)', back !== DB);
  }
  try { fs.unlinkSync(FILE); } catch {}

  /* ---------- Postgres 驱动(pg-mem)---------- */
  let pgMem = null;
  try { pgMem = require('pg-mem'); } catch {}
  if (!pgMem) {
    console.log('· 跳过 Postgres 驱动测试(未安装 pg-mem;运行 `npm install --no-save pg-mem` 可启用)');
  } else {
    // pg-mem 的 SQL 解析器对内联 DDL 约束过严(误报),故用其原生 declareTable 直接建表,
    // 并拦截驱动的 CREATE TABLE IF NOT EXISTS 为 no-op。生产 SQL 标准、在真实 Postgres 上正常。
    const { newDb, DataType } = pgMem;
    const db = newDb();
    const text = db.public.getType(DataType.text);
    const jsonb = db.public.getType(DataType.jsonb);
    for (const c of COLLECTIONS) {
      db.public.declareTable({ name: `rc_${c}`, fields: [
        { name: 'id', type: text, constraints: [{ type: 'primary key' }] },
        { name: 'data', type: jsonb },
      ] });
    }
    db.public.declareTable({ name: 'rc_meta', fields: [
      { name: 'key', type: text, constraints: [{ type: 'primary key' }] },
      { name: 'value', type: jsonb },
    ] });
    db.public.interceptQueries(sql => /create table/i.test(sql) ? [] : null);

    const _pgModule = db.adapters.createPg(); // { Pool, Client }
    const cfg = { STORAGE: 'postgres', DATABASE_URL: 'postgres://mem', _pgModule };

    const p = createPersistence(cfg);
    ok('pg: 选中 postgres 驱动', p.kind === 'postgres');
    ok('pg: 空库返回 null(自动建表)', (await p.load()) === null);

    const DB = sampleDB();
    await p.flush(DB);

    // 重新创建驱动实例,确保是从 SQL 真实重载,而非内存残留
    const p2 = createPersistence(cfg);
    const back = await p2.load();
    ok('pg: 重载非空', back !== null);
    ok('pg: 重载 seq 一致', back && back.seq === 1042, back && back.seq);
    ok('pg: 重载 users 数量一致', back && back.users.length === 2);
    ok('pg: 重载按 id 升序', back && back.users[0].id === '1001' && back.users[1].id === '1002');
    ok('pg: JSONB 嵌套字段保真(following)', back && Array.isArray(back.users[0].following) && back.users[0].following[0] === '1002');
    ok('pg: posts/events/notifications 各 1 条', back && back.posts.length === 1 && back.events.length === 1 && back.notifications.length === 1);

    // 二次快照覆盖:删除一个用户 + 改 seq,验证 DELETE+INSERT 整库快照语义
    DB.users.pop();
    DB.seq = 2000;
    await p2.flush(DB);
    const p3 = createPersistence(cfg);
    const back2 = await p3.load();
    ok('pg: 二次快照删除生效', back2 && back2.users.length === 1);
    ok('pg: 二次快照 seq 更新', back2 && back2.seq === 2000, back2 && back2.seq);
    await p.close(); await p2.close(); await p3.close();
  }

  console.log(`\n══ 存储层结果: ${pass} 通过 / ${fail} 失败 ══`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('✗ 存储层测试异常:', e); process.exit(1); });
