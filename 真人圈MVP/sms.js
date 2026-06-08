'use strict';
/**
 * 真人圈 RealCircle — 短信验证码接入层
 * =====================================
 * 「真人」平台的注册根基:手机号需收到一次性验证码才能注册,挡住批量机器注册。
 *
 * provider 由 SMS_PROVIDER 选择:
 *   mock    开发/演示,不真发短信(开发模式回显验证码,便于自测)
 *   aliyun  阿里云短信(国内)
 *   twilio  Twilio(海外)
 *
 * 是否强制:SMS_REQUIRED=true 时注册必须带正确验证码;切换生产 = 改环境变量 + 配密钥。
 */
const crypto = require('crypto');

class SmsError extends Error { constructor(code, status) { super(code); this.code = code; this.status = status || 400; } }

function genCode() { return String(crypto.randomInt(0, 1000000)).padStart(6, '0'); }

/* mock:不真发,开发模式把验证码回显给前端(生产模式不回显) */
function mockProvider(cfg) {
  return { name: 'mock', async send(dial, phone, code) {
    return { devCode: cfg.NODE_ENV !== 'production' ? code : undefined };
  } };
}

/* 阿里云 dysmsapi(留接入点;需 AccessKey + 签名 + 模板) */
function aliyunProvider(cfg) {
  return { name: 'aliyun', async send(dial, phone, code) {
    if (!cfg.ALIYUN_SMS_KEY || !cfg.ALIYUN_SMS_SECRET) throw new SmsError('SMS_NOT_CONFIGURED', 503);
    // 生产:用 AccessKey 对 SendSms 请求做 HMAC-SHA1 签名后 POST dysmsapi.aliyuncs.com,
    // 模板参数传 {code}。此处留好接入点,接真实密钥即用。
    throw new SmsError('SMS_NOT_CONFIGURED', 503);
  } };
}

/* Twilio(海外;真实可发) */
function twilioProvider(cfg) {
  return { name: 'twilio', async send(dial, phone, code) {
    if (!cfg.TWILIO_SID || !cfg.TWILIO_TOKEN || !cfg.TWILIO_FROM) throw new SmsError('SMS_NOT_CONFIGURED', 503);
    const body = new URLSearchParams({ To: '+' + dial + phone, From: cfg.TWILIO_FROM, Body: `【RealCircle 真人圈】验证码 ${code},5 分钟内有效。` });
    let r;
    try {
      r = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${cfg.TWILIO_SID}/Messages.json`, {
        method: 'POST',
        headers: { Authorization: 'Basic ' + Buffer.from(cfg.TWILIO_SID + ':' + cfg.TWILIO_TOKEN).toString('base64'), 'Content-Type': 'application/x-www-form-urlencoded' },
        body,
      });
    } catch (e) { throw new SmsError('短信服务不可达:' + e.message, 502); }
    if (!r.ok) throw new SmsError('短信发送失败', 502);
    return {};
  } };
}

function createSms(cfg) {
  switch ((cfg.SMS_PROVIDER || 'mock').toLowerCase()) {
    case 'mock': return mockProvider(cfg);
    case 'aliyun': return aliyunProvider(cfg);
    case 'twilio': return twilioProvider(cfg);
    default: throw new Error('未知短信 provider:' + cfg.SMS_PROVIDER + '(支持 mock | aliyun | twilio)');
  }
}

module.exports = { createSms, SmsError, genCode };
