import 'package:flutter/material.dart';
import '../i18n.dart';
import '../theme.dart';
import '../realtime.dart';
import 'feed_screen.dart';
import 'video_screen.dart';
import 'events_screen.dart';
import 'chats_screen.dart';
import 'me_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _i = 0;
  final l = L10n.instance;

  @override
  void initState() {
    super.initState();
    Realtime.instance.connect(); // 进入主页(已 L2+)即建立实时连接,退出登录时断开
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const FeedScreen(), const VideoScreen(), const EventsScreen(), const ChatsScreen(), const MeScreen()];
    return Scaffold(
      body: IndexedStack(index: _i, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) => setState(() => _i = v),
        height: 62,
        backgroundColor: Colors.white,
        indicatorColor: kGreenL,
        destinations: [
          NavigationDestination(icon: const Text('🏠', style: TextStyle(fontSize: 20)), label: l.t('feed')),
          NavigationDestination(icon: const Text('🎬', style: TextStyle(fontSize: 20)), label: l.t('video')),
          NavigationDestination(icon: const Text('📍', style: TextStyle(fontSize: 20)), label: l.t('events')),
          NavigationDestination(icon: const Text('💬', style: TextStyle(fontSize: 20)), label: l.t('chat')),
          NavigationDestination(icon: const Text('👤', style: TextStyle(fontSize: 20)), label: l.t('me')),
        ],
      ),
    );
  }
}
