'use strict';
/**
 * 真人圈 RealCircle — 可插拔持久化层
 * =====================================
 * 后端业务逻辑只跟「内存工作集 DB」打交道(同步、简单、零依赖),
 * 真正的落盘交给这里的「持久化驱动」。换存储 = 换驱动,业务代码与三端零改动。
 *
 *   STORAGE=json      单文件 JSON + 原子写(默认,零第三方依赖)
 *   STORAGE=postgres  PostgreSQL 真实表(每个集合一张表 + JSONB 行),需 `npm install pg`
 *
 * 选择规则:显式 STORAGE 优先;否则设置了 DATABASE_URL 即用 postgres,反之 json。
 */
const fs = require('fs');

/* 所有需要持久化的集合(seq 作为 meta 单独存) */
const COLLECTIONS = ['users', 'posts', 'comments', 'messages', 'events', 'notifications', 'reports'];

function emptyDB() {
  return { users: [], posts: [], comments: [], messages: [], events: [], notifications: [], reports: [], seq: 1000 };
}

/* 字段兜底:老数据/部分集合缺失时补齐,保证业务层拿到的结构永远完整 */
function normalize(DB) {
  for (const k of COLLECTIONS) DB[k] = DB[k] || [];
  DB.seq = DB.seq || 1000;
  return DB;
}

/* ============================ JSON 文件驱动 ============================ */
/* 与原实现一致:防抖 + 临时文件原子重命名,进程崩溃不会损坏数据。 */
function jsonDriver(cfg) {
  const FILE = cfg.DATA_FILE;
  let timer = null;
  function writeNow(DB) {
    const tmp = FILE + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(DB));
    fs.renameSync(tmp, FILE);
  }
  return {
    kind: 'json',
    describe() { return `JSON 文件 (${FILE})`; },
    async load() {
      if (fs.existsSync(FILE)) return normalize(JSON.parse(fs.readFileSync(FILE, 'utf8')));
      return null; // null = 全新库,交由调用方 seed
    },
    save(DB) { clearTimeout(timer); timer = setTimeout(() => writeNow(DB), 150); },
    flush(DB) { clearTimeout(timer); writeNow(DB); },
    async close() {},
  };
}

/* ============================ PostgreSQL 驱动 ============================ */
/* 每个集合一张 rc_<name>(id TEXT 主键, data JSONB)真实表 + rc_meta 存 seq。
 * 内存工作集仍是唯一真值源,落盘 = 事务内整库快照(防抖 + 串行,MVP 规模足够)。
 * 规模上来后可平滑演进为「脏行增量 upsert / 事件溯源」,业务层无需改动。 */
function pgDriver(cfg) {
  let Pool;
  try { ({ Pool } = cfg._pgModule || require('pg')); } // _pgModule:测试可注入 pg 兼容实现(如 pg-mem)
  catch (_) {
    throw new Error('STORAGE=postgres 需要 pg 依赖。请在 真人圈MVP/ 下运行:npm install pg');
  }
  if (!cfg.DATABASE_URL) throw new Error('STORAGE=postgres 需要环境变量 DATABASE_URL(如 postgres://user:pass@host:5432/realcircle)');

  const pool = new Pool({
    connectionString: cfg.DATABASE_URL,
    max: parseInt(cfg.PG_POOL_MAX || '10', 10),
    ssl: cfg.PG_SSL === 'true' ? { rejectUnauthorized: false } : undefined,
  });

  let timer = null, saving = false, pending = false;

  async function ensureSchema() {
    for (const c of COLLECTIONS) {
      await pool.query(`CREATE TABLE IF NOT EXISTS rc_${c} (id TEXT PRIMARY KEY, data JSONB NOT NULL)`);
    }
    await pool.query(`CREATE TABLE IF NOT EXISTS rc_meta (key TEXT PRIMARY KEY, value JSONB NOT NULL)`);
  }

  async function snapshot(DB) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      for (const c of COLLECTIONS) {
        await client.query(`DELETE FROM rc_${c}`);
        const rows = DB[c] || [];
        for (let i = 0; i < rows.length; i += 500) {        // 分批,避免单条 SQL 参数过多
          const chunk = rows.slice(i, i + 500);
          const tuples = [], params = [];
          chunk.forEach((row, j) => {
            tuples.push(`($${j * 2 + 1}, $${j * 2 + 2})`);
            params.push(String(row.id), JSON.stringify(row));
          });
          await client.query(`INSERT INTO rc_${c} (id, data) VALUES ${tuples.join(',')}`, params);
        }
      }
      await client.query(
        `INSERT INTO rc_meta (key, value) VALUES ('seq', $1)
         ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
        [JSON.stringify(DB.seq)]
      );
      await client.query('COMMIT');
    } catch (e) {
      try { await client.query('ROLLBACK'); } catch (_) {}
      throw e;
    } finally {
      client.release();
    }
  }

  async function persist(DB) {
    if (saving) { pending = true; return; }   // 串行:进行中则标记待续,合并写
    saving = true;
    try { await snapshot(DB); }
    catch (e) { console.error('[pg] 持久化失败:', e.message); }
    finally {
      saving = false;
      if (pending) { pending = false; persist(DB); }
    }
  }

  return {
    kind: 'postgres',
    describe() { return 'PostgreSQL'; },
    async load() {
      await ensureSchema();
      const DB = emptyDB();
      let any = false;
      for (const c of COLLECTIONS) {
        const { rows } = await pool.query(`SELECT data FROM rc_${c} ORDER BY id::numeric`);
        DB[c] = rows.map(r => r.data);
        if (rows.length) any = true;
      }
      const meta = await pool.query(`SELECT value FROM rc_meta WHERE key = 'seq'`);
      if (meta.rows.length) { DB.seq = meta.rows[0].value; any = true; }
      return any ? normalize(DB) : null; // 空库 → null,交由调用方 seed
    },
    save(DB) { clearTimeout(timer); timer = setTimeout(() => persist(DB), 200); },
    async flush(DB) { clearTimeout(timer); await persist(DB); },
    async close() { try { await pool.end(); } catch (_) {} },
  };
}

/* ============================ 工厂 ============================ */
function createPersistence(cfg) {
  const mode = cfg.STORAGE || (cfg.DATABASE_URL ? 'postgres' : 'json');
  if (mode === 'postgres') return pgDriver(cfg);
  if (mode === 'json') return jsonDriver(cfg);
  throw new Error(`未知存储模式 STORAGE=${mode}(支持 json | postgres)`);
}

module.exports = { createPersistence, emptyDB, normalize, COLLECTIONS };
