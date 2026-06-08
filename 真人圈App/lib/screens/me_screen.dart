import 'package:flutter/material.dart';
import '../api.dart';
import '../i18n.dart';
import '../theme.dart';
import '../main.dart';
import '../realtime.dart';
import '../widgets/post_card.dart';

class MeScreen extends StatefulWidget {
  const MeScreen({super.key});
  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  final l = L10n.instance;
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      await Api.fetchMe();
      _data = await Api.user(Api.me!['id']);
    } catch (e) { if (mounted) toast(context, e.toString()); }
    if (mounted) setState(() => _loading = false);
  }

  void _edit() {
    final n = TextEditingController(text: Api.me!['nickname']);
    final b = TextEditingController(text: Api.me!['bio'] ?? '');
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 18, right: 18, top: 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l.t('edit'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(controller: n, maxLength: 20, decoration: InputDecoration(hintText: l.t('nick'))),
          const SizedBox(height: 8),
          TextField(controller: b, maxLength: 200, maxLines: 3, decoration: InputDecoration(hintText: l.t('bioEmpty'))),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              try { await Api.updateMe(nickname: n.text, bio: b.text); if (mounted) Navigator.pop(context); _load(); }
              catch (e) { if (mounted) toast(context, e.toString()); }
            },
            child: Text(l.t('save')),
          )),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _data == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final u = _data!['user'] as Map;
    final posts = _data!['posts'] as List;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: EdgeInsets.zero, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 40, 18, 22),
            decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kGreen, kGreenD])),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                avatar(u['nickname'] ?? '?', size: 58),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(u['nickname'] ?? '?', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
                    const SizedBox(width: 6), levelBadge(u['level'] ?? 1),
                  ]),
                  const SizedBox(height: 3),
                  Text('${_data!['levelName']} · ${u['bio']?.isNotEmpty == true ? u['bio'] : l.t('bioEmpty')}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ])),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                _stat('${u['followers']}', l.t('followers')),
                const SizedBox(width: 20),
                _stat('${u['following']}', l.t('followingC')),
                const SizedBox(width: 20),
                _stat('${u['meetCount']}', l.t('meet')),
              ]),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: _edit,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99))),
                child: Text(l.t('edit')),
              ),
            ]),
          ),
          Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            _tile('🔒', l.t('notif') == 'Notifications' ? 'Privacy' : '隐私中心', '人脸原图已删除 · 仅存特征哈希 · 不训练、不出境、不商用'),
            _tile('🏹', '猎手计划', '举报 AI 生成内容,经人工复审确认后获得现金奖励'),
            const SizedBox(height: 8),
            _langRow(),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: kGreen, side: const BorderSide(color: kGreen, width: 1.5), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
              onPressed: () async {
                Realtime.instance.disconnect();
                await Api.logout();
                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const Gate()), (r) => false);
                }
              },
              child: Text(l.t('logout'), style: const TextStyle(fontWeight: FontWeight.bold)),
            )),
            const SizedBox(height: 12),
            ...posts.map((p) => PostCard(p, onChanged: _load)),
          ])),
        ]),
      ),
    );
  }

  Widget _stat(String n, String label) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(n, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ]);

  Widget _tile(String ic, String title, String sub) => Card(child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Text(ic, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(sub, style: const TextStyle(fontSize: 12, color: kGray, height: 1.5)),
          ])),
        ]),
      ));

  Widget _langRow() {
    const labels = {'zh': '中文', 'en': 'EN', 'ar': 'عربي'};
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: labels.entries.map((e) {
      final on = l.lang == e.key;
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: GestureDetector(
        onTap: () => l.set(e.key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: on ? kGold : kGreenL, borderRadius: BorderRadius.circular(99)),
          child: Text(e.value, style: TextStyle(color: on ? kInk : kGreen, fontWeight: FontWeight.bold)),
        ),
      ));
    }).toList());
  }
}

