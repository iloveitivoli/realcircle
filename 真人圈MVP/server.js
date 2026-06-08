#!/usr/bin/env node
/**
 * 真人圈 RealCircle — 生产级后端服务
 * =====================================
 * 100% 真人社交平台。零第三方依赖,仅需 Node.js 18+,可直接部署运营。
 *
 * 运行:        node server.js
 * 环境变量:    PORT(默认3000) DATA_FILE NODE_ENV ADMIN_PHONE
 * 反向代理:    见 deploy/nginx.conf;容器化见 Dockerfile / docker-compose.yml
 *
 * 已实现:鉴权(scrypt+会话过期) · 限流 · 真人分级验证(活体模拟,留SDK接口) ·
 *        人脸去重 · 内容流/短视频/24h故事 · 评论 · 点赞 · 关注 · 通知 ·
 *        私信 · 线下活动 · 搜索 · AI内容文本检测拦截 · 举报与自动下架 ·
 *        多语言错误码 · 管理员审核接口
 */
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { createPersistence, emptyDB, normalize } = require('./storage');
const { createLiveness, LivenessError } = require('./liveness');
const wsHub = require('./ws');

/* ============================ 配置 ============================ */
const CFG = {
  PORT: parseInt(process.env.PORT || '3000', 10),
  DATA_FILE: process.env.DATA_FILE || path.join(__dirname, 'data.json'),
  PUBLIC_DIR: path.join(__dirname, 'public'),
  NODE_ENV: process.env.NODE_ENV || 'development',
  ADMIN_PHONE: process.env.ADMIN_PHONE || '13800000001',
  SESSION_TTL_MS: 1000 * 60 * 60 * 24 * 30, // 30天
  STORY_TTL_MS: 1000 * 60 * 60 * 24,        // 24小时
  RATE_WINDOW_MS: 60 * 1000,
  RATE_MAX: parseInt(process.env.RATE_MAX || '120', 10),            // 每分钟每IP
  RATE_MAX_WRITE: parseInt(process.env.RATE_MAX_WRITE || '30', 10), // 每分钟每IP写操作
  // 存储:json(默认,零依赖)| postgres(需 DATABASE_URL + npm install pg)
  STORAGE: process.env.STORAGE || (process.env.DATABASE_URL ? 'postgres' : 'json'),
  DATABASE_URL: process.env.DATABASE_URL || '',
  PG_POOL_MAX: process.env.PG_POOL_MAX || '10',
  PG_SSL: process.env.PG_SSL || 'false',
  // 活体验证 provider:mock(默认)| facetec | iproov
  LIVENESS_PROVIDER: process.env.LIVENESS_PROVIDER || 'mock',
};

/* ============================ 存储层 ============================ */
/* 内存工作集 DB 为唯一真值源(业务逻辑同步、简单);落盘交由可插拔驱动(见 storage.js)。
 * 换存储 = 换驱动,所有访问经下方 store.*,业务代码与三端零改动。 */
let DB = null;
let persistence = null;
const store = {
  async init() {
    persistence = createPersistence(CFG);
    const loaded = await persistence.load();
    if (loaded) {
      DB = normalize(loaded);
    } else {
      DB = emptyDB();
      seed(); // 全新库:写入种子数据(内部会调 store.save)
    }
    return persistence;
  },
  save() { if (persistence) persistence.save(DB); },
  flush() { if (persistence) return persistence.flush(DB); },
  close() { if (persistence) return persistence.close(); },
  nid() { return String(++DB.seq); },
};

/* ============================ 活体验证 provider ============================ */
const liveness = createLiveness(CFG);

/* ============================ 实时推送 Hub(WebSocket) ============================ */
let hub = null; // 在 server 创建后 attach;notify()/私信路由按需推送(离线则降级为轮询)

/* ============================ 安全 ============================ */
function hashPwd(pwd, salt) {
  salt = salt || crypto.randomBytes(16).toString('hex');
  return { salt, hash: crypto.scryptSync(pwd, salt, 64).toString('hex') };
}
function verifyPwd(pwd, salt, hash) {
  const h = crypto.scryptSync(pwd, salt, 64).toString('hex');
  return crypto.timingSafeEqual(Buffer.from(h), Buffer.from(hash));
}
/* 会话:token -> { uid, exp } */
const sessions = new Map();
function newToken(uid) {
  const t = crypto.randomBytes(24).toString('hex');
  sessions.set(t, { uid, exp: Date.now() + CFG.SESSION_TTL_MS });
  return t;
}
function uidFromToken(t) {
  const s = sessions.get(t);
  if (!s) return null;
  if (s.exp < Date.now()) { sessions.delete(t); return null; }
  return s.uid;
}

/* ============================ 限流 ============================ */
const rate = new Map(); // ip -> {count, writeCount, reset}
function rateLimit(ip, isWrite) {
  const now = Date.now();
  let r = rate.get(ip);
  if (!r || r.reset < now) { r = { count: 0, writeCount: 0, reset: now + CFG.RATE_WINDOW_MS }; rate.set(ip, r); }
  r.count++; if (isWrite) r.writeCount++;
  if (r.count > CFG.RATE_MAX) return false;
  if (isWrite && r.writeCount > CFG.RATE_MAX_WRITE) return false;
  return true;
}
setInterval(() => { const now = Date.now(); for (const [k, v] of rate) if (v.reset < now) rate.delete(k); }, 60000).unref?.();

/* ============================ AI 内容检测(文本侧拦截) ============================ */
/* MVP 启发式:命中明显的 AI 自述/模板话术则拦截。生产环境替换为多模型检测管线。*/
const AI_PATTERNS = [
  /作为(一个)?(AI|人工智能|大语言模型|语言模型)/i,
  /\bas an ai\b/i, /\bas a language model\b/i,
  /我(无法|不能)(提供|拥有)(真实)?(情感|身体|个人经历)/,
  /本(内容|视频|图片)由\s*AI\s*生成/i,
  /#?(midjourney|stable\s?diffusion|sora|生成式ai)/i,
];
function detectAIText(text) {
  for (const re of AI_PATTERNS) if (re.test(text)) return true;
  return false;
}

/* ============================ 种子数据 ============================ */
function seed() {
  const mk = (phone, nickname, level, bio) => {
    const { salt, hash } = hashPwd('demo123');
    const u = { id: store.nid(), phone, nickname, level, bio, salt, hash,
      faceHash: level >= 2 ? crypto.randomBytes(8).toString('hex') : null,
      meetCount: level >= 4 ? 5 : 0, following: [], created: Date.now() };
    DB.users.push(u); return u;
  };
  const a = mk('13800000001', '川子在拉萨', 4, '骑行中国第23天');
  const b = mk('13800000002', '阿瓜的木工房', 3, '手作木工,拒绝AI画图');
  const c = mk('13800000003', '茉茉', 4, '即兴戏剧爱好者');
  const d = mk('13800000004', '老周', 3, '徒步/黑胶/纪录片');
  const post = (u, text, kind, ago, story, media) => DB.posts.push({
    id: store.nid(), uid: u.id, text, kind: kind || 'text', direct: true,
    media: media || null, mediaType: media ? (kind === 'video' ? 'video' : 'image') : null,
    likes: [], reports: [], removed: false, story: !!story,
    ts: Date.now() - ago, expire: story ? Date.now() + CFG.STORY_TTL_MS : 0,
  });
  post(a, '骑行第23天,翻过最后一个垭口。手冻僵了,照片是抖的,但每一帧都是我亲眼看到的。', 'text', 7200e3);
  post(b, '这把椅子做了三周,手上添了两个新茧。AI能画一万把椅子,但坐不上去。', 'text', 18000e3);
  post(c, '第一次参加平台的陌生人饭局,6个人聊到店家打烊。', 'text', 86400e3);
  post(a, '随手拍的日出,没开滤镜。【平台示例短片 · 可拖动播放】', 'video', 3600e3, false, '/demo/v1.mp4');
  post(c, '练琴第100天,弹错了三个和弦,一刀未剪。【平台示例短片】', 'video', 5400e3, false, '/demo/v2.mp4');
  post(a, '此刻的拉萨夜空 🌌', 'text', 1800e3, true);  // 故事
  post(d, '出发前的咖啡 ☕', 'text', 3000e3, true);     // 故事
  DB.events.push(
    { id: store.nid(), title: '周四陌生人饭局 · 玉林路苍蝇馆子', time: '周四 19:00', fee: '¥15', cap: 6, minLevel: 2, members: [a.id, c.id, d.id] },
    { id: store.nid(), title: '周六龙泉山日出徒步 · 新手友好', time: '周六 04:30', fee: '免费', cap: 8, minLevel: 2, members: [d.id] },
    { id: store.nid(), title: '周日桌游下午茶 · 镋钯街', time: '周日 14:00', fee: '¥10', cap: 5, minLevel: 2, members: [c.id, a.id, b.id] },
  );
  store.save();
}

/* ============================ 工具 ============================ */
function json(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(obj));
}
function err(res, code, key) { json(res, code, { error: key }); } // key 为可被前端 i18n 的错误码/中文
function readBody(req) {
  return new Promise((resolve, reject) => {
    let raw = '';
    req.on('data', c => { raw += c; if (raw.length > 2e6) req.destroy(); });
    req.on('end', () => { try { resolve(raw ? JSON.parse(raw) : {}); } catch { reject(new Error('bad json')); } });
    req.on('error', reject);
  });
}
const U = id => DB.users.find(u => u.id === id);
function authUser(req) { const t = (req.headers.authorization || '').replace('Bearer ', ''); const uid = uidFromToken(t); return uid ? U(uid) : null; }
function pubUser(u, viewer) {
  if (!u) return { id: '?', nickname: '已注销', level: 1, bio: '', meetCount: 0, followers: 0, following: 0, isFollowing: false };
  return {
    id: u.id, nickname: u.nickname, level: u.level, bio: u.bio || '', meetCount: u.meetCount || 0,
    followers: DB.users.filter(x => (x.following || []).includes(u.id)).length,
    following: (u.following || []).length,
    isFollowing: viewer ? (viewer.following || []).includes(u.id) : false,
  };
}
const LEVEL_NAMES = { 1: 'L1 基础', 2: 'L2 活体', 3: 'L3 实名', 4: 'L4 面验' };
function notify(toUid, type, fromUid, extra) {
  if (toUid === fromUid) return;
  const n = { id: store.nid(), to: toUid, type, from: fromUid, extra: extra || {}, read: false, ts: Date.now() };
  DB.notifications.push(n);
  if (hub) hub.toUser(toUid, { type: 'notify', notification: { id: n.id, type: n.type, ts: n.ts, from: pubUser(U(fromUid)), extra: n.extra } });
}
function livePosts() { const now = Date.now(); return DB.posts.filter(p => !p.removed && (!p.story || p.expire > now)); }
/* 多国手机号:区号 dial(默认 86)+ 本地号 phone;一人一号去重按 (dial,phone)。
 * 中国 +86 保留严格校验,其它国家按通用长度校验。 */
function normDial(d) { return String(d || '86').replace(/\D/g, '') || '86'; }
function normPhone(p) { return String(p || '').replace(/[\s-]/g, ''); }
function validPhone(dial, phone) {
  if (!/^\d+$/.test(phone)) return false;
  if (dial === '86') return /^1\d{10}$/.test(phone);   // 中国大陆
  return phone.length >= 5 && phone.length <= 14;       // 通用 E.164 本地段
}
function findUserByPhone(dial, phone) { return DB.users.find(x => x.phone === phone && normDial(x.dial) === dial); }

/* ============================ 路由 ============================ */
const routes = {
  /* ---- 健康检查(部署探活) ---- */
  'GET /api/health': async (_q, res) => json(res, 200, { ok: true, env: CFG.NODE_ENV, users: DB.users.length, ts: Date.now() }),

  /* ---- 账号 ---- */
  'POST /api/register': async (req, res) => {
    const body = await readBody(req);
    const dial = normDial(body.dial), phone = normPhone(body.phone), { password, nickname } = body;
    if (!validPhone(dial, phone)) return err(res, 400, '手机号格式不正确');
    if (!password || password.length < 6) return err(res, 400, '密码至少6位');
    if (!nickname || !nickname.trim()) return err(res, 400, '昵称不能为空');
    if (nickname.length > 20) return err(res, 400, '昵称过长');
    if (findUserByPhone(dial, phone)) return err(res, 409, '该手机号已注册(一人一号)');
    const { salt, hash } = hashPwd(password);
    const u = { id: store.nid(), phone, dial, nickname: nickname.trim(), level: 1, bio: '', salt, hash, faceHash: null, meetCount: 0, following: [], created: Date.now() };
    DB.users.push(u); store.save();
    json(res, 200, { token: newToken(u.id), user: pubUser(u) });
  },
  'POST /api/login': async (req, res) => {
    const body = await readBody(req);
    const dial = normDial(body.dial), phone = normPhone(body.phone), password = body.password;
    const u = findUserByPhone(dial, phone);
    if (!u || !verifyPwd(password || '', u.salt, u.hash)) return err(res, 401, '手机号或密码错误');
    json(res, 200, { token: newToken(u.id), user: pubUser(u), levelName: LEVEL_NAMES[u.level] });
  },
  'POST /api/logout': async (req, res) => {
    const t = (req.headers.authorization || '').replace('Bearer ', ''); sessions.delete(t);
    json(res, 200, { ok: true });
  },
  'GET /api/me': async (req, res) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    json(res, 200, { user: pubUser(u, u), levelName: LEVEL_NAMES[u.level], isAdmin: u.phone === CFG.ADMIN_PHONE });
  },
  'POST /api/me': async (req, res) => { // 编辑资料
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    const { nickname, bio } = await readBody(req);
    if (nickname !== undefined) { if (!nickname.trim() || nickname.length > 20) return err(res, 400, '昵称不合法'); u.nickname = nickname.trim(); }
    if (bio !== undefined) { if (bio.length > 200) return err(res, 400, '简介过长'); u.bio = bio; }
    store.save(); json(res, 200, { user: pubUser(u, u) });
  },

  /* ---- 活体验证(provider 抽象;mock/facetec/iproov,见 liveness.js,仅存特征哈希) ---- */
  'POST /api/liveness': async (req, res) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    const body = await readBody(req);
    let result;
    try {
      result = await liveness.verify(body);            // 厂商侧校验活体 + 取回特征哈希
    } catch (e) {
      if (e instanceof LivenessError) return err(res, e.status, e.code);
      if (CFG.NODE_ENV !== 'production') console.error(e);
      return err(res, 502, '活体服务异常');
    }
    const faceHash = result.faceHash;
    if (DB.users.find(x => x.id !== u.id && x.faceHash === faceHash)) return err(res, 409, '该面容已注册过账号(一人一号)');
    u.faceHash = faceHash; if (u.level < 2) u.level = 2; store.save();
    json(res, 200, { user: pubUser(u, u), message: '活体验证通过,原始图像已删除', provider: result.provider });
  },

  /* ---- 内容流 / 短视频 / 故事 ---- */
  'GET /api/posts': async (req, res, q) => {
    const viewer = authUser(req);
    const kind = q.get('kind');           // text | video | null(全部非故事)
    const scope = q.get('scope');         // following | null
    const before = parseInt(q.get('before') || '0', 10) || Date.now() + 1;
    let list = livePosts().filter(p => !p.story);
    if (kind) list = list.filter(p => p.kind === kind);
    if (scope === 'following' && viewer) { const set = new Set(viewer.following || []); list = list.filter(p => set.has(p.uid) || p.uid === viewer.id); }
    list = list.filter(p => p.ts < before).sort((a, b) => b.ts - a.ts).slice(0, 20);
    json(res, 200, { posts: list.map(p => serializePost(p, viewer)) });
  },
  'GET /api/stories': async (req, res) => {
    const viewer = authUser(req);
    const now = Date.now();
    const groups = {};
    for (const p of DB.posts.filter(x => x.story && !x.removed && x.expire > now).sort((a, b) => a.ts - b.ts)) {
      (groups[p.uid] = groups[p.uid] || []).push(serializePost(p, viewer));
    }
    json(res, 200, { stories: Object.entries(groups).map(([uid, items]) => ({ user: pubUser(U(uid), viewer), items })) });
  },
  'POST /api/posts': async (req, res) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    if (u.level < 2) return err(res, 403, '发布内容需要 L2 活体验证');
    if (!rateLimit('post:' + u.id, true)) return err(res, 429, '发布过于频繁,请稍后');
    const { text, kind, direct, story, media, mediaType } = await readBody(req);
    // 媒体只接受本平台上传返回的 /uploads/ 路径(防注入外链)
    const mediaUrl = (typeof media === 'string' && /^\/uploads\/[\w.-]+$/.test(media)) ? media : null;
    const mType = mediaUrl ? (['video', 'image'].includes(mediaType) ? mediaType : 'image') : null;
    const txt = (text || '').trim();
    if (!txt && !mediaUrl) return err(res, 400, '内容不能为空');     // 纯媒体帖允许无文字
    if (txt.length > 2000) return err(res, 400, '内容过长');
    if (txt && detectAIText(txt)) return err(res, 422, 'AI_BLOCKED'); // 命中AI检测,拒绝
    const realKind = mType === 'video' ? 'video' : (['text', 'video'].includes(kind) ? kind : 'text');
    const p = { id: store.nid(), uid: u.id, text: txt, kind: realKind,
      media: mediaUrl, mediaType: mType,
      direct: direct !== false, likes: [], reports: [], removed: false, story: !!story,
      ts: Date.now(), expire: story ? Date.now() + CFG.STORY_TTL_MS : 0 };
    DB.posts.push(p); store.save();
    json(res, 200, { id: p.id, post: serializePost(p, u) });
  },
  /* ---- 媒体上传(流式,零依赖;真实视频/图片,原始二进制 body) ---- */
  'PUT /api/upload': async (req, res) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    if (u.level < 2) return err(res, 403, '上传需要 L2 活体验证');
    if (!rateLimit('upload:' + u.id, true)) return err(res, 429, '上传过于频繁,请稍后');
    const ct = (req.headers['content-type'] || '').split(';')[0].trim().toLowerCase();
    const EXT = { 'video/mp4': 'mp4', 'video/webm': 'webm', 'video/quicktime': 'mov', 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif' };
    const kind = ct.startsWith('video/') ? 'video' : ct.startsWith('image/') ? 'image' : null;
    if (!kind || !EXT[ct]) return err(res, 415, '仅支持 mp4/webm/mov 视频或 jpg/png/webp/gif 图片');
    const max = kind === 'video' ? 25 * 1024 * 1024 : 6 * 1024 * 1024;
    const dir = path.join(CFG.PUBLIC_DIR, 'uploads');
    try { fs.mkdirSync(dir, { recursive: true }); } catch {}
    const name = store.nid() + '_' + crypto.randomBytes(4).toString('hex') + '.' + EXT[ct];
    const fp = path.join(dir, name);
    const stream = fs.createWriteStream(fp);
    let size = 0, aborted = false;
    const fail = (code, key) => { aborted = true; try { req.destroy(); } catch {} try { stream.destroy(); } catch {} fs.unlink(fp, () => {}); if (!res.headersSent) err(res, code, key); };
    req.on('data', c => { size += c.length; if (size > max && !aborted) fail(413, kind === 'video' ? '视频不能超过 25MB' : '图片不能超过 6MB'); });
    req.pipe(stream);
    await new Promise(resolve => { stream.on('finish', resolve); stream.on('error', resolve); req.on('error', resolve); });
    if (aborted) return;
    if (size === 0) { fs.unlink(fp, () => {}); return err(res, 400, '空文件'); }
    json(res, 200, { url: '/uploads/' + name, type: kind });
  },
  'POST /api/posts/:id/like': async (req, res, _q, params) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    const p = livePosts().find(x => x.id === params.id); if (!p) return err(res, 404, '内容不存在');
    const i = p.likes.indexOf(u.id);
    if (i >= 0) p.likes.splice(i, 1); else { p.likes.push(u.id); notify(p.uid, 'like', u.id, { pid: p.id }); }
    store.save(); json(res, 200, { likes: p.likes.length, liked: i < 0 });
  },
  'POST /api/posts/:id/report': async (req, res, _q, params) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    const p = livePosts().find(x => x.id === params.id); if (!p) return err(res, 404, '内容不存在');
    if (!p.reports.includes(u.id)) p.reports.push(u.id);
    DB.reports.push({ id: store.nid(), pid: p.id, by: u.id, ts: Date.now(), status: 'pending' });
    if (p.reports.length >= 3) p.removed = true;
    store.save();
    json(res, 200, { message: '已提交人工复审,感谢守护真人圈', autoRemoved: p.removed });
  },
  'DELETE /api/posts/:id': async (req, res, _q, params) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    const p = DB.posts.find(x => x.id === params.id); if (!p) return err(res, 404, '内容不存在');
    if (p.uid !== u.id && u.phone !== CFG.ADMIN_PHONE) return err(res, 403, '无权删除');
    p.removed = true; store.save(); json(res, 200, { ok: true });
  },

  /* ---- 评论 ---- */
  'GET /api/posts/:id/comments': async (req, res, _q, params) => {
    const viewer = authUser(req);
    const list = DB.comments.filter(c => c.pid === params.id && !c.removed).sort((a, b) => a.ts - b.ts);
    json(res, 200, { comments: list.map(c => ({ id: c.id, text: c.text, ts: c.ts, author: pubUser(U(c.uid), viewer) })) });
  },
  'POST /api/posts/:id/comments': async (req, res, _q, params) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    if (u.level < 2) return err(res, 403, '评论需要 L2 活体验证');
    const p = livePosts().find(x => x.id === params.id); if (!p) return err(res, 404, '内容不存在');
    const { text } = await readBody(req);
    if (!text || !text.trim()) return err(res, 400, '评论不能为空');
    if (text.length > 500) return err(res, 400, '评论过长');
    if (detectAIText(text)) return err(res, 422, 'AI_BLOCKED');
    const c = { id: store.nid(), pid: p.id, uid: u.id, text: text.trim(), removed: false, ts: Date.now() };
    DB.comments.push(c); notify(p.uid, 'comment', u.id, { pid: p.id }); store.save();
    json(res, 200, { id: c.id });
  },

  /* ---- 关注 ---- */
  'POST /api/users/:id/follow': async (req, res, _q, params) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    if (params.id === u.id) return err(res, 400, '不能关注自己');
    const target = U(params.id); if (!target) return err(res, 404, '用户不存在');
    u.following = u.following || [];
    const i = u.following.indexOf(params.id);
    if (i >= 0) u.following.splice(i, 1); else { u.following.push(params.id); notify(params.id, 'follow', u.id, {}); }
    store.save(); json(res, 200, { isFollowing: i < 0, followers: pubUser(target, u).followers });
  },

  /* ---- 通知 ---- */
  'GET /api/notifications': async (req, res) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    const list = DB.notifications.filter(n => n.to === u.id).sort((a, b) => b.ts - a.ts).slice(0, 50)
      .map(n => ({ id: n.id, type: n.type, read: n.read, ts: n.ts, from: pubUser(U(n.from), u), extra: n.extra }));
    json(res, 200, { notifications: list, unread: DB.notifications.filter(n => n.to === u.id && !n.read).length });
  },
  'POST /api/notifications/read': async (req, res) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    DB.notifications.forEach(n => { if (n.to === u.id) n.read = true; }); store.save();
    json(res, 200, { ok: true });
  },

  /* ---- 私信 ---- */
  'GET /api/conversations': async (req, res) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    const convs = {};
    for (const m of DB.messages) {
      if (m.from !== u.id && m.to !== u.id) continue;
      const other = m.from === u.id ? m.to : m.from;
      if (!convs[other] || convs[other].ts <= m.ts) convs[other] = m;
    }
    const list = Object.entries(convs).map(([oid, m]) => ({ user: pubUser(U(oid), u), last: m.text, ts: m.ts }))
      .sort((a, b) => b.ts - a.ts);
    json(res, 200, { conversations: list });
  },
  'GET /api/messages': async (req, res, q) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    const other = q.get('with');
    const msgs = DB.messages.filter(m => (m.from === u.id && m.to === other) || (m.from === other && m.to === u.id))
      .sort((a, b) => a.ts - b.ts).slice(-200);
    json(res, 200, { messages: msgs, me: u.id });
  },
  'POST /api/messages': async (req, res) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    if (u.level < 2) return err(res, 403, '聊天需要 L2 活体验证');
    if (!rateLimit('msg:' + u.id, true)) return err(res, 429, '发送过于频繁');
    const { to, text } = await readBody(req);
    if (!U(to)) return err(res, 404, '用户不存在');
    if (!text || !text.trim()) return err(res, 400, '消息不能为空');
    const m = { id: store.nid(), from: u.id, to, text: text.trim().slice(0, 2000), ts: Date.now() };
    DB.messages.push(m); notify(to, 'message', u.id, {}); store.save();
    // 实时推送给接收方 + 发送方其它在线设备(客户端按消息 id 去重)
    if (hub) { const evt = { type: 'message', message: m }; hub.toUser(to, evt); hub.toUser(u.id, evt); }
    json(res, 200, { id: m.id, ts: m.ts });
  },

  /* ---- 用户 / 搜索 ---- */
  'GET /api/users': async (req, res, q) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    let list = DB.users.filter(x => x.id !== u.id);
    const kw = (q.get('q') || '').trim();
    if (kw) list = list.filter(x => x.nickname.includes(kw) || (x.bio || '').includes(kw));
    json(res, 200, { users: list.map(x => pubUser(x, u)).sort((a, b) => b.level - a.level).slice(0, 50) });
  },
  'GET /api/users/:id': async (req, res, _q, params) => {
    const viewer = authUser(req);
    const u = U(params.id); if (!u) return err(res, 404, '用户不存在');
    const posts = livePosts().filter(p => p.uid === u.id && !p.story).sort((a, b) => b.ts - a.ts).slice(0, 20);
    json(res, 200, { user: pubUser(u, viewer), levelName: LEVEL_NAMES[u.level], posts: posts.map(p => serializePost(p, viewer)) });
  },
  'GET /api/search': async (req, res, q) => {
    const viewer = authUser(req);
    const kw = (q.get('q') || '').trim();
    if (!kw) return json(res, 200, { users: [], posts: [] });
    const users = DB.users.filter(x => x.nickname.includes(kw) || (x.bio || '').includes(kw)).slice(0, 10).map(x => pubUser(x, viewer));
    const posts = livePosts().filter(p => !p.story && p.text.includes(kw)).slice(0, 20).map(p => serializePost(p, viewer));
    json(res, 200, { users, posts });
  },

  /* ---- 线下活动 ---- */
  'GET /api/events': async (req, res) => {
    const u = authUser(req);
    json(res, 200, { events: DB.events.map(e => ({ ...e,
      members: e.members.map(id => pubUser(U(id), u)), joined: u ? e.members.includes(u.id) : false })) });
  },
  'POST /api/events': async (req, res) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    if (u.level < 3) return err(res, 403, '发起活动需要 L3 实名认证');
    const { title, time, fee, cap } = await readBody(req);
    if (!title || !title.trim()) return err(res, 400, '活动标题不能为空');
    const e = { id: store.nid(), title: title.trim(), time: time || '待定', fee: fee || '免费',
      cap: Math.min(Math.max(parseInt(cap, 10) || 6, 2), 50), minLevel: 2, members: [u.id] };
    DB.events.push(e); store.save(); json(res, 200, { id: e.id });
  },
  'POST /api/events/:id/join': async (req, res, _q, params) => {
    const u = authUser(req); if (!u) return err(res, 401, '请先登录');
    const e = DB.events.find(x => x.id === params.id); if (!e) return err(res, 404, '活动不存在');
    if (u.level < e.minLevel) return err(res, 403, `报名需要 ${LEVEL_NAMES[e.minLevel]} 及以上`);
    if (e.members.includes(u.id)) return err(res, 409, '已报名');
    if (e.members.length >= e.cap) return err(res, 409, '已满员');
    e.members.push(u.id); store.save();
    json(res, 200, { message: '报名成功,到场互扫即得「面验」进度', seats: `${e.members.length}/${e.cap}` });
  },

  /* ---- 管理员:审核队列 ---- */
  'GET /api/admin/reports': async (req, res) => {
    const u = authUser(req); if (!u || u.phone !== CFG.ADMIN_PHONE) return err(res, 403, '需要管理员权限');
    const pending = DB.posts.filter(p => p.reports.length > 0).map(p => ({
      post: serializePost(p, u), reports: p.reports.length, removed: p.removed }));
    json(res, 200, { queue: pending });
  },
  'POST /api/admin/posts/:id/restore': async (req, res, _q, params) => {
    const u = authUser(req); if (!u || u.phone !== CFG.ADMIN_PHONE) return err(res, 403, '需要管理员权限');
    const p = DB.posts.find(x => x.id === params.id); if (!p) return err(res, 404, '内容不存在');
    p.removed = false; p.reports = []; store.save(); json(res, 200, { ok: true });
  },
};

function serializePost(p, viewer) {
  return {
    id: p.id, text: p.text, kind: p.kind, direct: p.direct, story: p.story, ts: p.ts,
    media: p.media || null, mediaType: p.mediaType || null,
    likes: p.likes.length, liked: viewer ? p.likes.includes(viewer.id) : false,
    comments: DB.comments.filter(c => c.pid === p.id && !c.removed).length,
    author: pubUser(U(p.uid), viewer), mine: viewer ? p.uid === viewer.id : false,
  };
}

/* ============================ HTTP 入口 ============================ */
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.svg': 'image/svg+xml', '.json': 'application/json', '.webmanifest': 'application/manifest+json', '.ico': 'image/x-icon',
  '.mp4': 'video/mp4', '.webm': 'video/webm', '.mov': 'video/quicktime', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.gif': 'image/gif' };
const WRITE_METHODS = new Set(['POST', 'PUT', 'DELETE', 'PATCH']);

const server = http.createServer(async (req, res) => {
  const ip = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
  // 安全响应头
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'SAMEORIGIN');
  res.setHeader('Referrer-Policy', 'no-referrer-when-downgrade');
  // CORS(供移动端/跨域调用)
  res.setHeader('Access-Control-Allow-Origin', process.env.CORS_ORIGIN || '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }

  let url;
  try { url = new URL(req.url, 'http://x'); } catch { return err(res, 400, 'bad url'); }

  if (url.pathname.startsWith('/api/')) {
    if (!rateLimit(ip, WRITE_METHODS.has(req.method))) return err(res, 429, '请求过于频繁,请稍后再试');
    try {
      const exact = routes[`${req.method} ${url.pathname}`];
      if (exact) return await exact(req, res, url.searchParams, {});
      for (const key of Object.keys(routes)) {
        const sp = key.indexOf(' ');
        const m = key.slice(0, sp), pattern = key.slice(sp + 1);
        if (m !== req.method || !pattern.includes(':')) continue;
        const re = new RegExp('^' + pattern.replace(/:[^/]+/g, '([^/]+)') + '$');
        const match = url.pathname.match(re);
        if (match) {
          const names = (pattern.match(/:[^/]+/g) || []).map(s => s.slice(1));
          const params = {}; names.forEach((n, i) => params[n] = decodeURIComponent(match[i + 1]));
          return await routes[key](req, res, url.searchParams, params);
        }
      }
      return err(res, 404, 'not found');
    } catch (e) {
      if (CFG.NODE_ENV !== 'production') console.error(e);
      return err(res, 500, '服务器错误');
    }
  }

  // 静态资源(SPA fallback 到 index.html;视频/图片支持 Range 与流式)
  if (req.method === 'GET') {
    let rel = url.pathname === '/' ? '/index.html' : url.pathname;
    let fp = path.join(CFG.PUBLIC_DIR, path.normalize(rel));
    if (!fp.startsWith(CFG.PUBLIC_DIR)) return err(res, 403, 'forbidden');
    let isFile = fs.existsSync(fp) && fs.statSync(fp).isFile();
    if (!isFile) { fp = path.join(CFG.PUBLIC_DIR, 'index.html'); isFile = fs.existsSync(fp); }
    if (isFile) {
      const ext = path.extname(fp).toLowerCase();
      const mime = (MIME[ext] || 'application/octet-stream') + (ext === '.html' || ext === '.js' || ext === '.css' ? '; charset=utf-8' : '');
      const stat = fs.statSync(fp);
      if (fp.startsWith(path.join(CFG.PUBLIC_DIR, 'uploads'))) res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
      const range = req.headers.range;
      if (range && /^bytes=\d*-\d*$/.test(range)) { // 视频拖动:返回 206 局部
        let [s, e] = range.replace('bytes=', '').split('-');
        let start = parseInt(s, 10), end = e ? parseInt(e, 10) : stat.size - 1;
        if (isNaN(start)) start = 0;
        if (isNaN(end) || end >= stat.size) end = stat.size - 1;
        if (start > end || start >= stat.size) { res.writeHead(416, { 'Content-Range': `bytes */${stat.size}` }); return res.end(); }
        res.writeHead(206, { 'Content-Type': mime, 'Content-Range': `bytes ${start}-${end}/${stat.size}`, 'Accept-Ranges': 'bytes', 'Content-Length': end - start + 1 });
        return fs.createReadStream(fp, { start, end }).pipe(res);
      }
      res.writeHead(200, { 'Content-Type': mime, 'Content-Length': stat.size, 'Accept-Ranges': 'bytes' });
      return fs.createReadStream(fp).pipe(res);
    }
  }
  err(res, 404, 'not found');
});

/* WebSocket 实时推送:挂到同一 server,token 鉴权复用会话校验 */
hub = wsHub.attach(server, uidFromToken, { path: '/ws' });

/* 优雅退出:落盘 + 关闭连接池 */
let shuttingDown = false;
async function shutdown() {
  if (shuttingDown) return; shuttingDown = true;
  try { await store.flush(); } catch {}
  try { await store.close(); } catch {}
  process.exit(0);
}
process.on('SIGINT', shutdown); process.on('SIGTERM', shutdown);

if (require.main === module) {
  store.init()
    .then(() => server.listen(CFG.PORT, () =>
      console.log(`真人圈 RealCircle 运行中 → http://localhost:${CFG.PORT}  [${CFG.NODE_ENV}] 存储:${persistence.describe()}`)))
    .catch(e => { console.error('启动失败:', e.message); process.exit(1); });
}
module.exports = { server, store, CFG };
