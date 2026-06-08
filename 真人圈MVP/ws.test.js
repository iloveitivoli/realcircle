#!/usr/bin/env node
/** 真人圈 — WebSocket 实时推送集成测试。
 *  真实启动 server.js,用零依赖手写 WS 客户端连接,通过 REST 发私信/触发通知,
 *  断言对端 WS 实时收到 message / notify 帧。 */
'use strict';
const { spawn } = require('child_process');
const net = require('net');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PORT = 3911;
const BASE = `http://localhost:${PORT}`;
const TMP_DATA = path.join(os.tmpdir(), `rc-ws-${process.pid}.json`);

let pass = 0, fail = 0;
function ok(name, cond, extra) { cond ? pass++ : fail++; console.log(`${cond ? '✓' : '✗'} ${name}${cond ? '' : '  ←—— ' + (extra || '')}`); }
async function req(method, p, body, token) {
  const r = await fetch(BASE + p, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: body ? JSON.stringify(body) : undefined });
  return { status: r.status, data: await r.json().catch(() => ({})) };
}
async function mkUser(phone, nick, face) {
  const r = await req('POST', '/api/register', { phone, password: 'pass888', nickname: nick });
  await req('POST', '/api/liveness', { faceSample: face }, r.data.token);
  return { token: r.data.token, id: (await req('GET', '/api/me', null, r.data.token)).data.user.id };
}

/* 最小 WS 客户端:握手 + 解析服务端文本帧(不掩码),客户端发送需掩码 */
function wsConnect(token, onJson) {
  return new Promise((resolve, reject) => {
    const socket = net.connect(PORT, 'localhost', () => {
      const key = crypto.randomBytes(16).toString('base64');
      socket.write(
        `GET /ws?token=${token} HTTP/1.1\r\nHost: localhost:${PORT}\r\n` +
        `Upgrade: websocket\r\nConnection: Upgrade\r\n` +
        `Sec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`
      );
    });
    let handshook = false, buf = Buffer.alloc(0);
    socket.on('data', chunk => {
      buf = Buffer.concat([buf, chunk]);
      if (!handshook) {
        const i = buf.indexOf('\r\n\r\n');
        if (i === -1) return;
        const head = buf.subarray(0, i).toString();
        if (!/101 Switching Protocols/.test(head)) return reject(new Error('握手失败: ' + head.split('\r\n')[0]));
        handshook = true;
        buf = buf.subarray(i + 4);
        resolve({ socket, close: () => socket.destroy() });
      }
      // 解析服务端帧(server→client 不掩码)
      parse();
      function parse() {
        for (;;) {
          if (buf.length < 2) return;
          const opcode = buf[0] & 0x0f;
          let len = buf[1] & 0x7f, off = 2;
          if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
          else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); off = 10; }
          if (buf.length < off + len) return;
          const payload = buf.subarray(off, off + len);
          buf = buf.subarray(off + len);
          if (opcode === 0x1) { try { onJson(JSON.parse(payload.toString('utf8'))); } catch {} }
        }
      }
    });
    socket.on('error', reject);
  });
}
const wait = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  if (fs.existsSync(TMP_DATA)) fs.unlinkSync(TMP_DATA);
  const srv = spawn(process.execPath, [path.join(__dirname, 'server.js')], { env: { ...process.env, PORT, DATA_FILE: TMP_DATA, NODE_ENV: 'production', ADMIN_PHONE: '13800000001', RATE_MAX: '100000', RATE_MAX_WRITE: '100000' }, stdio: 'pipe' });
  await new Promise(r => srv.stdout.once('data', r));

  try {
    const alice = await mkUser('13900007001', 'Alice', 'wsfaceA');
    const bob = await mkUser('13900007002', 'Bob', 'wsfaceB');

    /* Bob 建立 WS */
    const bobEvents = [];
    const bobWs = await wsConnect(bob.token, e => bobEvents.push(e));
    await wait(150);
    ok('WS 握手成功并收到 connected', bobEvents.some(e => e.type === 'connected' && e.uid === bob.id), JSON.stringify(bobEvents));

    /* 鉴权:坏 token 应被拒(握手失败) */
    let badRejected = false;
    try { await wsConnect('bad-token', () => {}); } catch { badRejected = true; }
    ok('坏 token WS 握手被拒', badRejected);

    /* Alice 经 REST 给 Bob 发私信 → Bob 的 WS 实时收到 message */
    const before = bobEvents.length;
    await req('POST', '/api/messages', { to: bob.id, text: '实时你好 👋' }, alice.token);
    await wait(250);
    const msgEvt = bobEvents.slice(before).find(e => e.type === 'message');
    ok('私信实时推送到接收方', !!msgEvt && msgEvt.message.text.includes('实时你好'), JSON.stringify(bobEvents.slice(before)));
    ok('推送消息字段完整', !!msgEvt && msgEvt.message.from === alice.id && msgEvt.message.to === bob.id);

    /* Alice 关注 Bob → Bob 实时收到 notify */
    const before2 = bobEvents.length;
    await req('POST', `/api/users/${bob.id}/follow`, null, alice.token);
    await wait(250);
    const notifyEvt = bobEvents.slice(before2).find(e => e.type === 'notify' && e.notification.type === 'follow');
    ok('关注通知实时推送', !!notifyEvt && notifyEvt.notification.from.id === alice.id, JSON.stringify(bobEvents.slice(before2)));

    /* 离线用户不报错:Carol 无 WS,发消息仍 200(降级轮询) */
    const carol = await mkUser('13900007003', 'Carol', 'wsfaceC');
    const r = await req('POST', '/api/messages', { to: carol.id, text: '离线也能收(轮询兜底)' }, alice.token);
    ok('向离线用户发消息正常返回', r.status === 200);

    bobWs.close();
    await wait(100);
  } catch (e) { fail++; console.error('✗ WS 测试异常:', e); }
  finally { srv.kill(); try { fs.unlinkSync(TMP_DATA); } catch {} }

  console.log(`\n══ WebSocket 结果: ${pass} 通过 / ${fail} 失败 ══`);
  process.exit(fail ? 1 : 0);
})();
