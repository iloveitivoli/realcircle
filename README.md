# 真人圈 RealCircle

> 100% 真人社交平台 · 拒绝 AI 生成内容与虚拟人 · 网页 + Android + iOS 三端

互联网正在被非人流量淹没(2024 年机器人流量已占全网 51%)。真人圈反其道而行:每个账号都是活体验证过的真人,每条内容都出自人手,AI 在平台里只做「安检员」用于拦截 AI 内容,绝不生产内容。

## 项目结构

```
真人社交/
├── 真人圈产品方案.docx      完整商业方案(定位/九平台融合/强验证/商业模式/出海路线)
├── 真人圈原型.html          早期可点击原型(产品演示用)
├── 真人圈MVP/               ✅ 生产级网页应用(可直接部署运营)
│   ├── server.js              零依赖 Node 后端(鉴权/限流/审核/原子落盘)
│   ├── public/                三语 SPA 前端(中/英/阿 + RTL)
│   ├── test.js                59 项集成测试(全通过)
│   ├── Dockerfile             容器镜像
│   ├── docker-compose.yml     一键部署(含 Nginx)
│   └── deploy/nginx.conf      反向代理 + HTTPS 模板
└── 真人圈App/               ✅ Flutter 移动端(Android + iOS 一套代码)
    └── lib/                    对接与网页端完全相同的后端 API
```

## 三端关系

```
            ┌─────────────────────────────────────┐
            │     server.js (Node REST API)        │  ← 唯一数据与真人验证中枢
            └───────┬──────────────┬───────────────┘
                    │              │
        ┌───────────▼──┐   ┌───────▼────────────┐
        │ public/ 网页  │   │ 真人圈App/ Flutter  │
        │ (SPA, PWA)   │   │ (Android + iOS)    │
        └──────────────┘   └────────────────────┘
```

后端任何升级(活体模拟→金融级 SDK、JSON→PostgreSQL)三端同时生效。

## 快速开始

```bash
# 网页端(本地)
cd 真人圈MVP && node server.js        # → http://localhost:3000
node test.js                          # 跑测试

# 网页端(生产,Docker)
cd 真人圈MVP && docker compose up -d   # → http://服务器IP

# 移动端
cd 真人圈App && flutter create . && flutter pub get && flutter run
```

体验账号(密码 `demo123`):`13800000001`(L4,管理员)、`13800000004`(L3)。

## 当前完成度

| 模块 | 状态 |
|---|---|
| 商业方案文档 | ✅ 完成 |
| 网页端(全功能 + 三语 + 部署配置) | ✅ 生产级,92 测试通过 |
| 移动端(Flutter,Android+iOS) | ✅ 完整代码,本地 `flutter run` 即可 |
| 存储层 | ✅ 可插拔驱动:JSON(零依赖)/ PostgreSQL(真实表),一键切换 |
| 真人验证活体 | ✅ provider 抽象:mock / FaceTec / iProov,生产切换只改环境变量 |
| 实时私信 | ✅ 零依赖 WebSocket 实时推送,轮询为降级兜底 |
| 端到端加密私信 | ✅ ECDH P-256 + AES-GCM,服务器零知识(只存密文) |
| 直拍设备签名 | ✅ ECDSA 设备签名验真,防上传 AI 图冒充实拍 |
| 内容审核后台 | ✅ 数据看板 / 内容审核(下架·恢复) / 用户封禁 |
| 短信验证码 + 多国区号 | ✅ provider 抽象(mock/阿里云/Twilio),20 国区号 |
| 真实视频 | ✅ 上传 / Range 流式 / 抖音式自动播放 |
| 第三方密钥对接(活体/短信) | ⚠️ 接入点与请求契约已就绪,填密钥即用 |
| iOS 上架签名打包 | ⬜ 需你的 Mac + Apple 开发者账号 |

> 移动端 Flutter:注册区号/短信、实时私信已同步;端到端加密与相机直拍的客户端 UI 为第二期(需 `flutter pub get` 接入 `web_socket_channel`、相机/加密库)。Web 端三项均已完成。

详见各子目录 README。
