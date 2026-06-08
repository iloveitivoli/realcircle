import 'package:flutter/material.dart';
import '../api.dart';
import '../i18n.dart';
import '../theme.dart';

class PostCard extends StatefulWidget {
  final Map post;
  final VoidCallback? onChanged;
  const PostCard(this.post, {super.key, this.onChanged});
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  final l = L10n.instance;
  late Map p = widget.post;

  Future<void> _like() async {
    try {
      final r = await Api.like(p['id']);
      setState(() { p['liked'] = r['liked']; p['likes'] = r['likes']; });
    } catch (e) { if (mounted) toast(context, e.toString()); }
  }

  Future<void> _report() async {
    try {
      final r = await Api.report(p['id']);
      if (mounted) toast(context, r['message'].toString());
      if (r['autoRemoved'] == true) widget.onChanged?.call();
    } catch (e) { if (mounted) toast(context, e.toString()); }
  }

  void _comments() {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => CommentSheet(pid: p['id']),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = p['author'] as Map;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            avatar(a['nickname'] ?? '?'),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(a['nickname'] ?? '?', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(width: 4), levelBadge(a['level'] ?? 1),
              ]),
              Text(timeAgo(p['ts']) + (p['kind'] == 'video' ? ' · 🎬' : ''),
                  style: const TextStyle(fontSize: 11, color: kGray)),
            ]),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(p['text'] ?? '', style: const TextStyle(fontSize: 14.5, height: 1.6)),
          ),
          if (p['direct'] == true)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: kGreenL, borderRadius: BorderRadius.circular(99)),
              child: const Text('📷 App 直拍 · 已签名', style: TextStyle(fontSize: 10, color: kGreen, fontWeight: FontWeight.w800)),
            ),
          Row(children: [
            _act(p['liked'] == true ? '❤️' : '🤍', '${p['likes']}', _like, p['liked'] == true),
            const SizedBox(width: 20),
            _act('💬', '${p['comments']}', _comments, false),
            const Spacer(),
            _act('⚠', l.t('reportAI'), _report, false),
          ]),
        ]),
      ),
    );
  }

  Widget _act(String ic, String label, VoidCallback onTap, bool active) {
    return InkWell(
      onTap: onTap,
      child: Row(children: [
        Text(ic, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 13, color: active ? const Color(0xFFD64545) : kGray)),
      ]),
    );
  }
}

class CommentSheet extends StatefulWidget {
  final String pid;
  const CommentSheet({super.key, required this.pid});
  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final l = L10n.instance;
  final _c = TextEditingController();
  List _list = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try { _list = await Api.comments(widget.pid); } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _send() async {
    if (_c.text.trim().isEmpty) return;
    try { await Api.addComment(widget.pid, _c.text); _c.clear(); _load(); }
    catch (e) {
      if (mounted) toast(context, (e is ApiException && e.code == 'AI_BLOCKED') ? l.t('aiblocked') : e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(18),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l.t('comment'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Flexible(
            child: _loading
                ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                : _list.isEmpty
                    ? Padding(padding: const EdgeInsets.all(20), child: Text(l.t('hello'), style: const TextStyle(color: kGray)))
                    : ListView(shrinkWrap: true, children: _list.map((c) {
                        final a = c['author'] as Map;
                        return ListTile(
                          leading: avatar(a['nickname'] ?? '?', size: 32),
                          title: Row(children: [Text(a['nickname'] ?? '?', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), const SizedBox(width: 4), levelBadge(a['level'] ?? 1)]),
                          subtitle: Text(c['text'] ?? ''),
                        );
                      }).toList()),
          ),
          Row(children: [
            Expanded(child: TextField(controller: _c, decoration: InputDecoration(hintText: l.t('comment')))),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _send, child: Text(l.t('send'))),
          ]),
        ]),
      ),
    );
  }
}
