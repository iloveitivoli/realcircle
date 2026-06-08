#!/usr/bin/env node
/** 真人圈 RealCircle — 生产级集成测试 (node test.js,零依赖,真实启动服务器) */
'use strict';
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const PORT = 3901;
const BASE = `http://localhost:${PORT}`;
const TMP_DATA = path.join(os.tmpdir(), `rc-test-${process.pid}.json`);

let pass = 0, fail = 0;
function ok(name, cond, extra) { cond ? pass++ : fail++; console.log(`${cond ? '✓' : '✗'} ${name}${cond ? '' : '  ←—— ' + (extra || '')}`); }
async function req(method, p, body, token) {
  const r = await fetch(BASE + p, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: body ? JSON.stringify(body) : undefined });
  return { status: r.status, data: await r.json().catch(() => ({})) };
}
async function mkUser(phone, nick, face) {
  const r = await req('POST', '/api/register', { phone, password: 'pass888', nickname: nick });
  await req('POST', '/api/liveness', { faceSample: face }, r.data.token);
  return r.data.token;
}

(async () => {
  if (fs.existsSync(TMP_DATA)) fs.unlinkSync(TMP_DATA);
  const srv = spawn(process.execPath, [path.join(__dirname, 'server.js')], { env: { ...process.env, PORT, DATA_FILE: TMP_DATA, NODE_ENV: 'production', ADMIN_PHONE: '13800000001', RATE_MAX: '100000', RATE_MAX_WRITE: '100000' }, stdio: 'pipe' });
  await new Promise(r => srv.stdout.once('data', r));

  try {
    /* ---- 健康检查 ---- */
    let r = await req('GET', '/api/health');
    ok('健康检查 ok', r.status === 200 && r.data.ok === true);

    /* ---- 注册校验 ---- */
    r = await req('POST', '/api/register', { phone: '13900001111', password: 'pass888', nickname: '测试一号' });
    ok('注册返回token+L1', r.status === 200 && r.data.token && r.data.user.level === 1);
    const t1 = r.data.token, u1 = r.data.user;
    ok('重复手机号被拒', (await req('POST', '/api/register', { phone: '13900001111', password: 'pass888', nickname: 'x' })).status === 409);
    ok('非法手机号被拒', (await req('POST', '/api/register', { phone: '123', password: 'pass888', nickname: 'x' })).status === 400);
    ok('弱密码被拒', (await req('POST', '/api/register', { phone: '13900002222', password: '123', nickname: 'x' })).status === 400);
    ok('空昵称被拒', (await req('POST', '/api/register', { phone: '13900002222', password: 'pass888', nickname: '' })).status === 400);

    /* ---- 登录 ---- */
    ok('错误密码登录失败', (await req('POST', '/api/login', { phone: '13900001111', password: 'wrong' })).status === 401);
    ok('正确密码登录成功', (await req('POST', '/api/login', { phone: '13900001111', password: 'pass888' })).status === 200);

    /* ---- L1 权限挡板 ---- */
    ok('L1 不能发帖', (await req('POST', '/api/posts', { text: 'x' }, t1)).status === 403);
    ok('L1 不能聊天', (await req('POST', '/api/messages', { to: '1001', text: 'x' }, t1)).status === 403);

    /* ---- 活体 + 人脸去重 ---- */
    r = await req('POST', '/api/liveness', { faceSample: 'face-one' }, t1);
    ok('活体升级L2', r.status === 200 && r.data.user.level === 2);
    r = await req('POST', '/api/register', { phone: '13900003333', password: 'pass888', nickname: '测试二号' });
    const t2 = r.data.token;
    ok('同面容二次注册被拒', (await req('POST', '/api/liveness', { faceSample: 'face-one' }, t2)).status === 409);
    ok('新面容验证通过', (await req('POST', '/api/liveness', { faceSample: 'face-two' }, t2)).status === 200);

    /* ---- 内容流 + 短视频 ---- */
    r = await req('POST', '/api/posts', { text: '我的第一条真人动态', direct: true }, t1);
    ok('L2 发帖成功', r.status === 200 && r.data.id);
    const pid = r.data.id;
    r = await req('POST', '/api/posts', { text: '竖屏直拍视频', kind: 'video' }, t1);
    ok('发短视频成功', r.status === 200);
    r = await req('GET', '/api/posts');
    ok('内容流含新帖+种子帖', r.status === 200 && r.data.posts.length >= 4 && r.data.posts[0].text.includes('第一条') === false || r.data.posts.some(p => p.text.includes('第一条')));
    r = await req('GET', '/api/posts?kind=video');
    ok('视频流只含视频', r.data.posts.length >= 1 && r.data.posts.every(p => p.kind === 'video'));

    /* ---- AI 内容检测拦截 ---- */
    r = await req('POST', '/api/posts', { text: '作为一个AI语言模型,我无法拥有真实情感' }, t1);
    ok('AI自述文本被拦截(422)', r.status === 422 && r.data.error === 'AI_BLOCKED');
    r = await req('POST', '/api/posts', { text: '本视频由AI生成,仅供娱乐' }, t1);
    ok('AI生成声明被拦截', r.status === 422);

    /* ---- 点赞 ---- */
    r = await req('POST', `/api/posts/${pid}/like`, null, t2);
    ok('点赞成功', r.status === 200 && r.data.likes === 1 && r.data.liked);
    r = await req('POST', `/api/posts/${pid}/like`, null, t2);
    ok('取消赞', r.data.likes === 0);

    /* ---- 评论 ---- */
    r = await req('POST', `/api/posts/${pid}/comments`, { text: '真实!支持' }, t2);
    ok('评论成功', r.status === 200);
    ok('AI评论被拦截', (await req('POST', `/api/posts/${pid}/comments`, { text: 'as an AI language model' }, t2)).status === 422);
    r = await req('GET', `/api/posts/${pid}/comments`);
    ok('评论列表正确', r.data.comments.length === 1 && r.data.comments[0].text.includes('支持'));

    /* ---- 关注 + 通知 ---- */
    const id1 = (await req('GET', '/api/me', null, t1)).data.user.id;
    const id2 = (await req('GET', '/api/me', null, t2)).data.user.id;
    r = await req('POST', `/api/users/${id1}/follow`, null, t2);
    ok('关注成功', r.status === 200 && r.data.isFollowing && r.data.followers === 1);
    ok('不能关注自己', (await req('POST', `/api/users/${id2}/follow`, null, t2)).status === 400);
    r = await req('GET', '/api/posts?scope=following', null, t2);
    ok('关注流含被关注者的帖', r.data.posts.some(p => p.author.id === id1));
    r = await req('GET', '/api/notifications', null, t1);
    ok('被点赞/评论/关注产生通知', r.status === 200 && r.data.notifications.length >= 2 && r.data.unread >= 2, JSON.stringify(r.data.unread));
    await req('POST', '/api/notifications/read', null, t1);
    ok('标记已读后unread归零', (await req('GET', '/api/notifications', null, t1)).data.unread === 0);

    /* ---- 资料编辑 ---- */
    r = await req('POST', '/api/me', { bio: '骑行爱好者' }, t1);
    ok('编辑简介成功', r.status === 200 && r.data.user.bio === '骑行爱好者');

    /* ---- 私信 ---- */
    ok('发私信成功', (await req('POST', '/api/messages', { to: id2, text: '你好,真人!' }, t1)).status === 200);
    await req('POST', '/api/messages', { to: id1, text: '你好你好 👋' }, t2);
    r = await req('GET', '/api/messages?with=' + id2, null, t1);
    ok('会话双向消息正确', r.data.messages.length === 2 && r.data.me === id1);
    r = await req('GET', '/api/conversations', null, t1);
    ok('会话列表正确', r.data.conversations.length === 1 && r.data.conversations[0].last.includes('👋'));

    /* ---- 搜索 ---- */
    r = await req('GET', '/api/search?q=' + encodeURIComponent('真人'), null, t1);
    ok('搜索返回结果', r.status === 200 && (r.data.posts.length > 0 || r.data.users.length >= 0));
    r = await req('GET', '/api/users?q=' + encodeURIComponent('测试二号'), null, t1);
    ok('按昵称搜人', r.data.users.some(u => u.nickname === '测试二号'));

    /* ---- 活动 ---- */
    r = await req('GET', '/api/events', null, t1);
    ok('活动列表3场', r.data.events.length === 3);
    const ev = r.data.events[0];
    ok('L2 报名成功', (await req('POST', `/api/events/${ev.id}/join`, null, t1)).status === 200);
    ok('重复报名被拒', (await req('POST', `/api/events/${ev.id}/join`, null, t1)).status === 409);
    ok('L2 不能发起活动(需L3)', (await req('POST', '/api/events', { title: '我的局' }, t1)).status === 403);

    /* ---- 举报自动下架 ---- */
    const tA = await mkUser('13900005551', '举报A', 'fA');
    const tB = await mkUser('13900005552', '举报B', 'fB');
    await req('POST', `/api/posts/${pid}/report`, null, t2);
    await req('POST', `/api/posts/${pid}/report`, null, tA);
    r = await req('POST', `/api/posts/${pid}/report`, null, tB);
    ok('3人举报自动下架', r.data.autoRemoved === true);
    ok('下架内容不在流中', !(await req('GET', '/api/posts')).data.posts.find(p => p.id === pid));

    /* ---- 管理员审核 ---- */
    const tAdmin = (await req('POST', '/api/login', { phone: '13800000001', password: 'demo123' })).data.token;
    r = await req('GET', '/api/admin/reports', null, tAdmin);
    ok('管理员可看审核队列', r.status === 200 && r.data.queue.length >= 1);
    ok('非管理员看队列被拒', (await req('GET', '/api/admin/reports', null, t1)).status === 403);
    r = await req('POST', `/api/admin/posts/${pid}/restore`, null, tAdmin);
    ok('管理员恢复内容', r.status === 200);
    ok('恢复后重现内容流', !!(await req('GET', '/api/posts')).data.posts.find(p => p.id === pid));

    /* ---- 故事(24h) ---- */
    r = await req('POST', '/api/posts', { text: '此刻的天空', story: true }, t1);
    ok('发故事成功', r.status === 200);
    r = await req('GET', '/api/stories', null, t1);
    ok('故事按人分组', r.status === 200 && r.data.stories.some(s => s.user.id === id1));
    ok('故事不进主内容流', !(await req('GET', '/api/posts')).data.posts.find(p => p.text === '此刻的天空'));

    /* ---- 删除 ---- */
    r = await req('POST', '/api/posts', { text: '待删除' }, t1);
    ok('删除自己的帖成功', (await req('DELETE', `/api/posts/${r.data.id}`, null, t1)).status === 200);
    r = await req('POST', '/api/posts', { text: '别人的帖' }, t1);
    ok('不能删除他人帖', (await req('DELETE', `/api/posts/${r.data.id}`, null, t2)).status === 403);

    /* ---- 安全 ---- */
    ok('伪造token被拒', (await req('GET', '/api/me', null, 'bad')).status === 401);
    ok('未登录访问私信被拒', (await req('GET', '/api/conversations')).status === 401);
    ok('登出后token失效', await (async () => { const tt = (await req('POST', '/api/login', { phone: '13900001111', password: 'pass888' })).data.token; await req('POST', '/api/logout', null, tt); return (await req('GET', '/api/me', null, tt)).status === 401; })());
    await new Promise(r => setTimeout(r, 400));
    const raw = fs.readFileSync(TMP_DATA, 'utf8');
    ok('落盘不含明文密码', !raw.includes('pass888'));
    const page = await fetch(BASE + '/'); ok('首页可访问', page.status === 200 && (await page.text()).includes('真人圈'));
    ok('SPA fallback', (await fetch(BASE + '/some/deep/route')).status === 200);
    { // 路径穿越:即便请求后端源码路径,也只能拿到 SPA 首页,绝不泄露 server.js 源码
      const tr = await fetch(BASE + '/server.js'); const body = await tr.text();
      ok('后端源码不被静态服务泄露', !body.includes('require(') && !body.includes('scryptSync'));
    }
    ok('安全响应头存在', (await fetch(BASE + '/')).headers.get('x-content-type-options') === 'nosniff');
    ok('manifest 可访问', (await fetch(BASE + '/manifest.webmanifest')).status === 200);

  } catch (e) { fail++; console.error('✗ 测试异常:', e); }
  finally { srv.kill(); try { fs.unlinkSync(TMP_DATA); } catch {} }
  console.log(`\n══ 结果: ${pass} 通过 / ${fail} 失败 ══`);
  process.exit(fail ? 1 : 0);
})();
