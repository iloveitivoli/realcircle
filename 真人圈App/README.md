# 真人圈 RealCircle — 移动端(Android + iOS)

Flutter 一套代码,同时构建 Android 与 iOS,对接与 Web 端**完全相同**的后端 API(`真人圈MVP/server.js`)。

## 目录结构

```
lib/
  main.dart            入口 + 路由门(未登录→认证;未验证→活体;已验证→主页)
  api.dart             REST 客户端(与 Web 同一套接口)
  realtime.dart        WebSocket 实时层(私信/通知即时推送,断线重连,轮询兜底)
  i18n.dart            中 / 英 / 阿三语,阿拉伯语自动 RTL
  theme.dart           主题、头像、徽章、工具函数
  screens/
    auth_screen.dart     登录 / 注册 + 语言切换
    verify_screen.dart   3D 活体验证(模拟,留 SDK 接口)
    home_screen.dart     底部 5 Tab 导航
    feed_screen.dart     真人圈内容流 + 故事栏 + 发帖
    video_screen.dart    全屏竖滑短视频(抖音式)
    events_screen.dart   线下活动列表 + 发起 + 报名
    chats_screen.dart    会话列表 + 1对1 聊天(加密标识)
    me_screen.dart       个人主页 + 编辑资料 + 语言 + 退出
  widgets/
    post_card.dart       帖子卡片 + 评论弹层
```

## 运行步骤

前置:安装 [Flutter SDK](https://docs.flutter.dev/get-started/install)(3.10+),并准备 Android Studio / Xcode。

```bash
# 1. 进入目录,生成各平台工程文件(android/ ios/)
cd 真人圈App
flutter create .            # 仅首次:补全平台目录,不会覆盖 lib/ 与 pubspec.yaml

# 2. 拉取依赖
flutter pub get

# 3. 先启动后端(另一个终端)
#    cd ../真人圈MVP && node server.js

# 4. 运行(自动选择已连接的设备/模拟器)
flutter run
#    指定后端地址(可选):
flutter run --dart-define=API_BASE=http://10.0.2.2:3000     # Android 模拟器访问宿主机
flutter run --dart-define=API_BASE=http://localhost:3000    # iOS 模拟器
flutter run --dart-define=API_BASE=https://your-domain.com  # 生产
```

## 打包发布

```bash
flutter build apk --release        # Android APK
flutter build appbundle --release  # Google Play 上架包(AAB)
flutter build ios --release        # iOS(随后用 Xcode Archive 上传 App Store)
```

iOS 上架需在 Mac 上用 Xcode 配置签名证书与 Bundle ID。

## 与 Web 端一致性

移动端与 Web 端调用同一组 REST 接口,共享同一份数据与真人验证体系。私信走同一套 `ws://<后端>/ws` 实时通道(token 子协议鉴权)。后端任何升级(如把活体模拟替换为金融级 SDK、把 JSON 存储换成 PostgreSQL)三端同时生效,无需改动客户端逻辑。
