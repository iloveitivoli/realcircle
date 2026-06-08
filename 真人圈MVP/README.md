# 真人圈 MVP(网页版)

100% 真人社交平台 MVP。**JSON 存储模式零第三方依赖**,只需 [Node.js](https://nodejs.org) 18+;可一键切换 PostgreSQL。

## 运行

```bash
node server.js                 # 默认 JSON 存储 + mock 活体,零依赖
```

打开浏览器访问 **http://localhost:3000**

体验账号(密码均为 `demo123`):`13800000001`(川子,L4)、`13800000004`(老周,L3),或直接注册新账号走完整流程:注册 → 活体验证 → 发帖/私信(实时)/报名活动。

## 测试

```bash
npm test                 # node test.js     —— 59 项端到端集成测试
node storage.test.js     # 存储层:JSON + PostgreSQL(pg-mem 真实 SQL 往返)
node liveness.test.js    # 活体 provider 抽象(mock / facetec / iproov)
node ws.test.js          # WebSocket 实时推送(真实启动服务 + 手写 WS 客户端)
```

合计 **92 项测试**,覆盖注册校验、人脸去重、等级权限、内容流、举报下架、私信、活动报名、安全(密码哈希、token、路径穿越),以及存储/活体/实时三层。

## 已实现

| 模块 | 说明 |
|---|---|
| 账号 | 手机号注册/登录,scrypt 加盐密码,Bearer token 会话 |
| 真人等级 | L1 基础 → L2 活体 → L3/L4 预留;人脸特征哈希一人一号 |
| 内容流 | 发帖(直拍标记)、点赞、举报疑似 AI(3 人举报自动下架进人工复审) |
| 私信 | 会话列表 + 1对1 聊天;**WebSocket 实时推送**,2.5s 轮询为降级兜底 |
| 线下局 | 活动列表、等级门槛、满员控制、报名 |
| 权限 | L1 仅可浏览;发帖/聊天/报名需 L2+ |
| **存储层** | 可插拔驱动:`json`(默认,零依赖)/ `postgres`(真实表 + JSONB),业务零改动,见 `storage.js` |
| **活体接入** | provider 抽象:`mock` / `facetec` / `iproov`,生产切换只改环境变量,见 `liveness.js` |
| **实时推送** | 零依赖 WebSocket(RFC6455 手写握手/帧编解码),token 鉴权,见 `ws.js` |

### 切换 PostgreSQL

```bash
npm install pg                 # 仅此模式需要(纯 JS)
export STORAGE=postgres
export DATABASE_URL=postgres://realcircle:realcircle@localhost:5432/realcircle
node server.js                 # 自动建表(rc_users / rc_posts / … + rc_meta)
# 或:docker compose up -d(已内置 postgres 服务,见 docker-compose.yml 注释切换)
```

### 切换金融级活体 SDK

```bash
export LIVENESS_PROVIDER=facetec      # 或 iproov
export FACETEC_API_URL=...  FACETEC_API_KEY=...
```
客户端 SDK 采集后,把会话结果经接口透传给后端校验;服务端仅留特征哈希做一人一号去重,**绝不存原图**。

## 生产化路线(剩余)

- ✅ 存储:data.json → PostgreSQL(可插拔驱动,已落地)
- ✅ 活体:模拟流程 → 金融级 SDK 接入点(FaceTec/iProov provider,已落地)
- ✅ 消息:轮询 → WebSocket 实时推送(已落地)
- ⬜ 消息端到端加密(Signal 协议)
- ⬜ 直拍:App 内相机 + 设备签名(C2PA 思路),Web 端 getUserMedia 直拍
- ⬜ AI 内容检测多模型管线 + 人工审核后台
- ⬜ iOS 上架签名打包(需 Mac + Apple 开发者账号)
