// 真人圈 RealCircle — Flutter 移动端入口(Android + iOS 同一套代码)
import 'package:flutter/material.dart';
import 'api.dart';
import 'i18n.dart';
import 'theme.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/verify_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.init();
  await L10n.instance.load();
  runApp(const RealCircleApp());
}

class RealCircleApp extends StatelessWidget {
  const RealCircleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: L10n.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'RealCircle',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          locale: L10n.instance.locale,
          // 阿拉伯语自动从右到左
          builder: (context, child) => Directionality(
            textDirection: L10n.instance.isRtl ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
          home: const Gate(),
        );
      },
    );
  }
}

/// 入口路由:未登录→认证;已登录未验证→活体;已验证→主页
class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (Api.loggedIn) {
      try {
        await Api.fetchMe();
      } catch (_) {
        await Api.logout();
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!Api.loggedIn) return AuthScreen(onDone: () => setState(() {}));
    final level = (Api.me?['level'] ?? 1) as int;
    if (level < 2) return VerifyScreen(onDone: () => setState(() {}));
    return const HomeScreen();
  }
}
