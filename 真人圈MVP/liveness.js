'use strict';
/**
 * 真人圈 RealCircle — 活体验证接入层
 * =====================================
 * 真正的活体检测在客户端 SDK 完成(捕获 3D 人脸 / 动作),服务端只做两件事:
 *   1) 向厂商服务校验「这次会话确实是真人活体」(防照片/翻拍/深伪);
 *   2) 取回一个稳定的「人脸特征哈希」用于一人一号去重 —— 绝不存储原始图像。
 *
 * provider 由 LIVENESS_PROVIDER 选择:
 *   mock     开发/演示,无外部依赖(默认)
 *   facetec  FaceTec 3D 活体(海外金融级)
 *   iproov   iProov 活体(海外金融级)
 *
 * 切换生产 SDK = 改环境变量 + 配密钥,服务端业务与三端客户端逻辑零改动。
 */
const crypto = require('crypto');

class LivenessError extends Error {
  constructor(code, status) { super(code); this.code = code; this.status = status || 400; }
}

/* 由稳定输入派生 16 位特征哈希(仅存哈希,满足一人一号去重) */
function stableHash(input) {
  return crypto.createHash('sha256').update(String(input)).digest('hex').slice(0, 16);
}

/* ---------------------------- mock ---------------------------- */
/* 与原实现语义一致:任意非空采样视为通过,faceHash 由采样稳定派生。
 * 额外:采样命中 spoof/fake/翻拍 关键词时模拟「活体未通过」,便于演示失败路径与前端文案。 */
const mockProvider = {
  name: 'mock',
  async verify(body) {
    const sample = body.faceSample;
    if (!sample) throw new LivenessError('活体采样缺失', 400);
    if (/spoof|fake|翻拍|照片/i.test(String(sample))) throw new LivenessError('活体检测未通过(疑似非真人)', 422);
    return { faceHash: stableHash(sample), score: 0.99, provider: 'mock' };
  },
};

/* --------------------------- FaceTec --------------------------- */
/* 客户端用 FaceTec SDK 采集 3D FaceScan,服务端把 sessionId/faceScan 交 FaceTec Server SDK
 * 校验活体并取回 faceMap 哈希。下面是请求/响应契约骨架,接真实端点即用。 */
function facetecProvider(cfg) {
  const base = (cfg.FACETEC_API_URL || '').replace(/\/$/, '');
  const key = cfg.FACETEC_API_KEY || '';
  return {
    name: 'facetec',
    async verify(body) {
      if (!base || !key) throw new LivenessError('LIVENESS_NOT_CONFIGURED', 503);
      const { sessionId, faceScan, auditTrailImage } = body;
      if (!sessionId && !faceScan) throw new LivenessError('缺少 FaceTec 会话(sessionId/faceScan)', 400);
      let resp;
      try {
        resp = await fetch(`${base}/liveness-3d`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-Device-Key': key },
          body: JSON.stringify({ sessionId, faceScan, auditTrailImage }),
        });
      } catch (e) { throw new LivenessError('活体服务不可达:' + e.message, 502); }
      if (!resp.ok) throw new LivenessError(`活体服务错误(${resp.status})`, 502);
      const data = await resp.json().catch(() => ({}));
      // 期望:{ wasProcessed, livenessProven, faceMapHash, externalDatabaseRefID }
      if (!data.livenessProven) throw new LivenessError('活体检测未通过', 422);
      const faceHash = data.faceMapHash || stableHash(data.externalDatabaseRefID || sessionId);
      return { faceHash: String(faceHash).slice(0, 32), score: 1, provider: 'facetec' };
    },
  };
}

/* ---------------------------- iProov ---------------------------- */
/* 客户端拿 token 跑活体后,服务端调 /claim/verify/validate 取结果。 */
function iproovProvider(cfg) {
  const base = (cfg.IPROOV_API_URL || '').replace(/\/$/, '');
  const key = cfg.IPROOV_API_KEY || '';
  const secret = cfg.IPROOV_API_SECRET || '';
  return {
    name: 'iproov',
    async verify(body) {
      if (!base || !key || !secret) throw new LivenessError('LIVENESS_NOT_CONFIGURED', 503);
      const { token, userId } = body;
      if (!token) throw new LivenessError('缺少 iProov 会话 token', 400);
      let resp;
      try {
        resp = await fetch(`${base}/claim/verify/validate`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ api_key: key, secret, token, user_id: userId || token }),
        });
      } catch (e) { throw new LivenessError('活体服务不可达:' + e.message, 502); }
      if (!resp.ok) throw new LivenessError(`活体服务错误(${resp.status})`, 502);
      const data = await resp.json().catch(() => ({}));
      // 期望:{ passed: true, token, frame }
      if (!data.passed) throw new LivenessError('活体检测未通过', 422);
      return { faceHash: stableHash(data.token || token), score: 1, provider: 'iproov' };
    },
  };
}

function createLiveness(cfg) {
  switch ((cfg.LIVENESS_PROVIDER || 'mock').toLowerCase()) {
    case 'mock': return mockProvider;
    case 'facetec': return facetecProvider(cfg);
    case 'iproov': return iproovProvider(cfg);
    default: throw new Error('未知活体 provider:' + cfg.LIVENESS_PROVIDER + '(支持 mock | facetec | iproov)');
  }
}

module.exports = { createLiveness, LivenessError, stableHash };
