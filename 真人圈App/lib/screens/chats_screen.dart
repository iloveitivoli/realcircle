import 'dart:async';
import 'package:flutter/material.dart';
import '../api.dart';
import '../i18n.dart';
import '../theme.dart';
import '../realtime.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});
  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final l = L10n.instance;
  List _convs = [];
  bool _loading = true;
  StreamSubscription? _rt;

  @override
  void initState() {
    super.initState();
    _load();
    // 实时:收到新私信/通知时刷新会话列表
    _rt = Realtime.instance.events.listen((e) {
      if (e['type'] == 'message' || e['type'] == 'notify') _load();
    });
  }

  @override
  void dispose() { _rt?.cancel(); super.dispose(); }

  Future<void> _load() async {
    try { _convs = await Api.conversations(); } catch (e) { if (mounted) toast(context, e.toString()); }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(l.t('chat')), actions: [
        Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: Text(l.t('encrypted'), style: const TextStyle(fontSize: 11, color: kGreen)))),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _convs.isEmpty
                  ? ListView(children: [Padding(padding: const EdgeInsets.all(30), child: Center(child: Text(l.t('noConv'), style: const TextStyle(color: kGray))))])
                  : ListView(padding: const EdgeInsets.all(12), children: _convs.map((c) {
                      final u = c['user'] as Map;
                      return Card(child: ListTile(
                        leading: avatar(u['nickname'] ?? '?', size: 44),
                        title: Row(children: [Text(u['nickname'] ?? '?', style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(width: 4), levelBadge(u['level'] ?? 1)]),
                        subtitle: Text(c['last'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Text(timeAgo(c['ts']), style: const TextStyle(fontSize: 11, color: kGray)),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(u))).then((_) => _load()),
                      ));
                    }).toList()),
            ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final Map user;
  const ChatScreen(this.user, {super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final l = L10n.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List _msgs = [];
  String _me = '';
  Timer? _timer;
  StreamSubscription? _rt;

  @override
  void initState() {
    super.initState();
    _load();
    // 实时:与当前对端相关的消息即时刷新
    _rt = Realtime.instance.events.listen((e) {
      if (e['type'] != 'message') return;
      final m = e['message'];
      if (m is Map && (m['from'] == widget.user['id'] || m['to'] == widget.user['id'])) _load();
    });
    // 轮询作为 WebSocket 不可用时的降级兜底
    _timer = Timer.periodic(const Duration(milliseconds: 2500), (_) => _load());
  }

  @override
  void dispose() { _timer?.cancel(); _rt?.cancel(); super.dispose(); }

  Future<void> _load() async {
    try {
      final d = await Api.messages(widget.user['id']);
      _msgs = d['messages'] as List;
      _me = d['me'] ?? '';
      if (mounted) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    if (_input.text.trim().isEmpty) return;
    final txt = _input.text;
    _input.clear();
    try { await Api.sendMessage(widget.user['id'], txt); _load(); }
    catch (e) { if (mounted) toast(context, e.toString()); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [Text(widget.user['nickname'] ?? '?'), const SizedBox(width: 6), levelBadge(widget.user['level'] ?? 1)]),
        actions: const [Padding(padding: EdgeInsets.only(right: 14), child: Center(child: Text('🔒', style: TextStyle(fontSize: 16))))],
      ),
      body: Column(children: [
        Expanded(child: _msgs.isEmpty
            ? Center(child: Text(l.t('hello'), style: const TextStyle(color: kGray)))
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: _msgs.length,
                itemBuilder: (_, i) {
                  final m = _msgs[i];
                  final mine = m['from'] == _me;
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
                      decoration: BoxDecoration(
                        color: mine ? kGreen : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(m['text'] ?? '', style: TextStyle(color: mine ? Colors.white : kInk, fontSize: 14)),
                    ),
                  );
                },
              )),
        Container(
          padding: const EdgeInsets.all(9),
          color: Colors.white,
          child: SafeArea(top: false, child: Row(children: [
            Expanded(child: TextField(controller: _input, decoration: InputDecoration(hintText: l.t('sayhi')), onSubmitted: (_) => _send())),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _send, child: Text(l.t('send'))),
          ])),
        ),
      ]),
    );
  }
}
