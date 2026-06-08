import 'package:flutter/material.dart';
import '../api.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/post_card.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});
  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  final l = L10n.instance;
  List _videos = [];
  bool _loading = true;
  static const _emoji = ['🎸', '🏔️', '🌊', '🎨', '🍜', '⛺'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try { _videos = await Api.posts(kind: 'video'); } catch (e) { if (mounted) toast(context, e.toString()); }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_videos.isEmpty) return Scaffold(body: Center(child: Text(l.t('empty'), style: const TextStyle(color: kGray))));
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: _videos.length,
        itemBuilder: (_, i) => _VideoPage(_videos[i], _emoji[i % _emoji.length], onChanged: _load),
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  final Map post;
  final String emoji;
  final VoidCallback onChanged;
  const _VideoPage(this.post, this.emoji, {required this.onChanged});
  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  final l = L10n.instance;
  late Map p = widget.post;

  Future<void> _like() async {
    try { final r = await Api.like(p['id']); setState(() { p['liked'] = r['liked']; p['likes'] = r['likes']; }); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final a = p['author'] as Map;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [avatarColor(a['nickname'] ?? '?'), const Color(0xFF0E1420)]),
      ),
      child: SafeArea(
        child: Stack(children: [
          Center(child: Text(widget.emoji, style: const TextStyle(fontSize: 90))),
          Positioned(
            right: 12, bottom: 90,
            child: Column(children: [
              avatar(a['nickname'] ?? '?', size: 44),
              const SizedBox(height: 18),
              _side(p['liked'] == true ? '❤️' : '🤍', '${p['likes']}', _like),
              const SizedBox(height: 18),
              _side('💬', '${p['comments']}', () => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => CommentSheet(pid: p['id']))),
              const SizedBox(height: 18),
              _side('⚠️', l.t('reportAI'), () async { try { final r = await Api.report(p['id']); if (mounted) toast(context, r['message'].toString()); } catch (_) {} }),
            ]),
          ),
          Positioned(
            left: 16, right: 70, bottom: 24,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('@${a['nickname']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(width: 6), levelBadge(a['level'] ?? 1),
              ]),
              const SizedBox(height: 6),
              Text(p['text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5)),
              const SizedBox(height: 6),
              const Text('🛡️ 直拍签名 · 未检测到 AI 痕迹', style: TextStyle(color: Colors.white60, fontSize: 10.5)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _side(String ic, String label, VoidCallback onTap) {
    return GestureDetector(onTap: onTap, child: Column(children: [
      Text(ic, style: const TextStyle(fontSize: 26)),
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
    ]));
  }
}
