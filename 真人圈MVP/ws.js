'use strict';
/**
 * 真人圈 RealCircle — 零依赖 WebSocket 实时推送
 * =====================================
 * 复用同一个 http.Server,监听 upgrade。私信/通知产生时即时推给在线接收方,
 * 客户端 2.5s 轮询作为降级兜底(离线期间/握手失败仍能收到)。
 *
 *   ws://host/ws?token=<会话token>
 *
 * 仅用 Node 内置 http + crypto 实现 RFC6455 握手与帧编解码,延续「零第三方依赖」。
 */
const crypto = require('crypto');

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

/* 服务端→客户端文本帧(不掩码) */
function encodeText(str) {
  const payload = Buffer.from(str, 'utf8');
  const len = payload.length;
  let header;
  if (len < 126) {
    header = Buffer.from([0x81, len]);
  } else if (len < 65536) {
    header = Buffer.alloc(4); header[0] = 0x81; header[1] = 126; header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10); header[0] = 0x81; header[1] = 127; header.writeBigUInt64BE(BigInt(len), 2);
  }
  return Buffer.concat([header, payload]);
}
/* 控制帧(close 0x8 / ping 0x9 / pong 0xA),payload < 126 */
function encodeControl(opcode, payload = Buffer.alloc(0)) {
  return Buffer.concat([Buffer.from([0x80 | opcode, payload.length]), payload]);
}

/* 增量帧解析器:跨 TCP 分片累积,解出完整帧后回调 */
function makeParser({ onText, onClose, onPing }) {
  let buf = Buffer.alloc(0);
  return chunk => {
    buf = Buffer.concat([buf, chunk]);
    for (;;) {
      if (buf.length < 2) return;
      const b0 = buf[0], b1 = buf[1];
      const opcode = b0 & 0x0f;
      const masked = (b1 & 0x80) !== 0;
      let len = b1 & 0x7f;
      let off = 2;
      if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); off = 10; }
      let mask;
      if (masked) { if (buf.length < off + 4) return; mask = buf.subarray(off, off + 4); off += 4; }
      if (buf.length < off + len) return;
      let payload = buf.subarray(off, off + len);
      if (masked) { const out = Buffer.alloc(len); for (let i = 0; i < len; i++) out[i] = payload[i] ^ mask[i & 3]; payload = out; }
      buf = buf.subarray(off + len);
      if (opcode === 0x8) { onClose && onClose(); return; }       // close
      else if (opcode === 0x9) { onPing && onPing(payload); }      // ping → 需回 pong
      else if (opcode === 0x1) { onText && onText(payload.toString('utf8')); } // text
      // 0x2 binary / 0xA pong / 0x0 continuation:本协议(JSON 文本)忽略
    }
  };
}

class Hub {
  constructor() { this.byUser = new Map(); this.sockets = new Set(); }
  add(uid, socket) {
    socket._uid = uid; this.sockets.add(socket);
    let set = this.byUser.get(uid);
    if (!set) { set = new Set(); this.byUser.set(uid, set); }
    set.add(socket);
  }
  remove(socket) {
    if (!this.sockets.delete(socket)) return;
    const set = this.byUser.get(socket._uid);
    if (set) { set.delete(socket); if (!set.size) this.byUser.delete(socket._uid); }
  }
  _send(socket, frame) {
    try { socket.write(frame); }
    catch { try { socket.destroy(); } catch {} this.remove(socket); }
  }
  /* 推送 JSON 给某用户的全部在线连接,返回送达连接数 */
  toUser(uid, obj) {
    const set = this.byUser.get(uid);
    if (!set || !set.size) return 0;
    const frame = encodeText(JSON.stringify(obj));
    let n = 0;
    for (const s of [...set]) { this._send(s, frame); n++; }
    return n;
  }
  online(uid) { return this.byUser.has(uid); }
  get count() { return this.sockets.size; }
}

/**
 * 挂到 http.Server 上。
 * @param server      http.Server
 * @param authToUid   (token) => uid|null  会话校验(传入 server.js 的 uidFromToken)
 * @param opts        { path='/ws', heartbeatMs=30000 }
 * @returns Hub
 */
function attach(server, authToUid, opts = {}) {
  const hub = new Hub();
  const PATH = opts.path || '/ws';

  server.on('upgrade', (req, socket) => {
    let url;
    try { url = new URL(req.url, 'http://x'); } catch { return socket.destroy(); }
    if (url.pathname !== PATH) { socket.write('HTTP/1.1 404 Not Found\r\n\r\n'); return socket.destroy(); }

    // token 来自 query(?token=)或 Sec-WebSocket-Protocol(浏览器无法设 header 时用 subprotocol 传)
    const proto = (req.headers['sec-websocket-protocol'] || '').split(',')[0].trim();
    const token = url.searchParams.get('token') || proto;
    const uid = token ? authToUid(token) : null;
    if (!uid) { socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n'); return socket.destroy(); }

    const key = req.headers['sec-websocket-key'];
    if (!key) return socket.destroy();
    const accept = crypto.createHash('sha1').update(key + GUID).digest('base64');
    socket.write(
      'HTTP/1.1 101 Switching Protocols\r\n' +
      'Upgrade: websocket\r\n' +
      'Connection: Upgrade\r\n' +
      (proto ? `Sec-WebSocket-Protocol: ${proto}\r\n` : '') +
      `Sec-WebSocket-Accept: ${accept}\r\n\r\n`
    );
    socket.setNoDelay(true);

    hub.add(uid, socket);
    hub._send(socket, encodeText(JSON.stringify({ type: 'connected', uid })));

    const parser = makeParser({
      onText: () => {},                                                   // 客户端经 REST 写,无需处理入站业务帧
      onClose: () => { hub._send(socket, encodeControl(0x8)); hub.remove(socket); try { socket.destroy(); } catch {} },
      onPing: payload => hub._send(socket, encodeControl(0xA, payload)),  // 回 pong
    });
    socket.on('data', d => { try { parser(d); } catch { hub.remove(socket); try { socket.destroy(); } catch {} } });
    socket.on('close', () => hub.remove(socket));
    socket.on('error', () => { hub.remove(socket); try { socket.destroy(); } catch {} });
  });

  // 服务端心跳:定期 ping,清理半死连接
  const hb = setInterval(() => {
    const ping = encodeControl(0x9);
    for (const s of [...hub.sockets]) hub._send(s, ping);
  }, opts.heartbeatMs || 30000);
  hb.unref && hb.unref();

  return hub;
}

module.exports = { attach, Hub, encodeText, encodeControl, makeParser };
