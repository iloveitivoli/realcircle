import 'package:flutter/material.dart';
import '../api.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/post_card.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final l = L10n.instance;
  final _post = TextEditingController();
  List _posts = [];
  List _stories = [];
  bool _loading = true;
  String _scope = 'all';
  bool _direct = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _posts = await Api.posts(scope: _scope == 'following' ? 'following' : null);
      _stories = await Api.stories();
    } catch (e) { if (mounted) toast(context, e.toString()); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _publish() async {
    if (_post.text.trim().isEmpty) return;
    try {
      await Api.createPost(_post.text, direct: _direct);
      _post.clear();
      _load();
    } catch (e) {
      if (mounted) toast(context, (e is ApiException && e.code == 'AI_BLOCKED') ? l.t('aiblocked') : e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: const [Text('真人', style: TextStyle(fontWeight: FontWeight.w800, color: kGreen)), Text('圈', style: TextStyle(fontWeight: FontWeight.w800))]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: kGreenL, borderRadius: BorderRadius.circular(99)),
              child: Text('✓ ${l.t('noai')}', style: const TextStyle(fontSize: 10, color: kGreen, fontWeight: FontWeight.w800)),
            )),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(12), children: [
                if (_stories.isNotEmpty) _storyBar(),
                _composer(),
                _segScope(),
                if (_posts.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Center(child: Text(l.t('empty'), style: const TextStyle(color: kGray)))),
                ..._posts.map((p) => PostCard(p, onChanged: _load)),
              ]),
      ),
    );
  }

  Widget _storyBar() {
    return SizedBox(
      height: 86,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        ..._stories.map((s) {
          final u = s['user'] as Map;
          return GestureDetector(
            onTap: () => toast(context, (s['items'] as List).last['text'].toString()),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [kGreen, kGold])),
                  child: avatar(u['nickname'] ?? '?', size: 52),
                ),
                const SizedBox(height: 3),
                SizedBox(width: 60, child: Text(u['nickname'] ?? '?', overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5))),
              ]),
            ),
          );
        }),
      ]),
    );
  }

  Widget _composer() {
    return Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        TextField(controller: _post, maxLines: 2, decoration: InputDecoration(hintText: l.t('placeholder'))),
        const SizedBox(height: 6),
        Row(children: [
          Checkbox(value: _direct, onChanged: (v) => setState(() => _direct = v ?? true), activeColor: kGreen),
          Expanded(child: Text('📷 ${l.t('direct')}', style: const TextStyle(fontSize: 12, color: kGray))),
          ElevatedButton(onPressed: _publish, child: Text(l.t('publish'))),
        ]),
      ]),
    ));
  }

  Widget _segScope() {
    Widget btn(String key, String label) {
      final on = _scope == key;
      return Expanded(child: GestureDetector(
        onTap: () { setState(() => _scope = key); _load(); },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: on ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(9),
              boxShadow: on ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 3)] : null),
          child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: kGreen, fontSize: 13)),
        ),
      ));
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: kGreenL, borderRadius: BorderRadius.circular(11)),
      child: Row(children: [btn('all', l.t('all')), btn('following', l.t('following'))]),
    );
  }
}
