#!/usr/bin/env node
/** 真人圈 — 活体验证接入层测试(provider 抽象,无需真实 SDK)。 */
'use strict';
const { createLiveness, LivenessError, stableHash } = require('./liveness');

let pass = 0, fail = 0;
function ok(name, cond, extra) { cond ? pass++ : fail++; console.log(`${cond ? '✓' : '✗'} ${name}${cond ? '' : '  ←—— ' + (extra || '')}`); }
async function expectErr(fn, status) {
  try { await fn(); return null; }
  catch (e) { return (e instanceof LivenessError && e.status === status) ? e : { wrong: e }; }
}

(async () => {
  /* ---- mock ---- */
  const mock = createLiveness({ LIVENESS_PROVIDER: 'mock' });
  ok('mock: 选中 mock provider', mock.name === 'mock');
  const r = await mock.verify({ faceSample: 'face-one' });
  ok('mock: 通过并返回 faceHash', r.faceHash === stableHash('face-one') && r.provider === 'mock');
  ok('mock: 同采样哈希稳定(去重基础)', (await mock.verify({ faceSample: 'face-one' })).faceHash === r.faceHash);
  ok('mock: 不同采样哈希不同', (await mock.verify({ faceSample: 'face-two' })).faceHash !== r.faceHash);
  ok('mock: 空采样 400', (await expectErr(() => mock.verify({}), 400)) instanceof LivenessError);
  ok('mock: 攻击样本(spoof)422', (await expectErr(() => mock.verify({ faceSample: 'a-spoof-photo' }), 422)) instanceof LivenessError);

  /* ---- facetec(未配置 → 503;配置后会真实发请求,这里只验证守卫)---- */
  const ft = createLiveness({ LIVENESS_PROVIDER: 'facetec' });
  ok('facetec: 选中 facetec provider', ft.name === 'facetec');
  ok('facetec: 未配置密钥 → 503 NOT_CONFIGURED',
    (await expectErr(() => ft.verify({ sessionId: 'x' }), 503))?.code === 'LIVENESS_NOT_CONFIGURED');

  /* ---- iproov(未配置 → 503)---- */
  const ip = createLiveness({ LIVENESS_PROVIDER: 'iproov' });
  ok('iproov: 选中 iproov provider', ip.name === 'iproov');
  ok('iproov: 未配置密钥 → 503', (await expectErr(() => ip.verify({ token: 't' }), 503))?.code === 'LIVENESS_NOT_CONFIGURED');

  /* ---- 未知 provider 抛错 ---- */
  let threw = false;
  try { createLiveness({ LIVENESS_PROVIDER: 'nope' }); } catch { threw = true; }
  ok('未知 provider 启动即报错', threw);

  console.log(`\n══ 活体层结果: ${pass} 通过 / ${fail} 失败 ══`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('✗ 活体层测试异常:', e); process.exit(1); });
