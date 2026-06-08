import 'package:flutter/material.dart';
import '../api.dart';
import '../i18n.dart';
import '../theme.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final l = L10n.instance;
  List _events = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try { _events = await Api.events(); } catch (e) { if (mounted) toast(context, e.toString()); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _join(String id) async {
    try { final r = await Api.joinEvent(id); if (mounted) toast(context, r['message'].toString()); _load(); }
    catch (e) { if (mounted) toast(context, e.toString()); }
  }

  void _create() {
    final t = TextEditingController(), tm = TextEditingController(), f = TextEditingController(), cap = TextEditingController(text: '6');
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 18, right: 18, top: 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l.t('newEvent'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(controller: t, decoration: const InputDecoration(hintText: '活动标题')),
          const SizedBox(height: 8),
          TextField(controller: tm, decoration: const InputDecoration(hintText: '时间')),
          const SizedBox(height: 8),
          TextField(controller: f, decoration: const InputDecoration(hintText: '费用')),
          const SizedBox(height: 8),
          TextField(controller: cap, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: '人数上限')),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              try { await Api.createEvent(t.text, tm.text, f.text, int.tryParse(cap.text) ?? 6); if (mounted) Navigator.pop(context); _load(); }
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
    final level = (Api.me?['level'] ?? 1) as int;
    return Scaffold(
      appBar: AppBar(title: Text(l.t('events'))),
      floatingActionButton: level >= 3 ? FloatingActionButton.extended(onPressed: _create, backgroundColor: kGreen, icon: const Icon(Icons.add), label: Text(l.t('newEvent'))) : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                Container(
                  padding: const EdgeInsets.all(11), margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(color: kGreenL, borderRadius: BorderRadius.circular(12)),
                  child: const Text('⭐ 被 3 位实名用户当面确认,解锁最高「面验」徽章。', style: TextStyle(fontSize: 12, color: kGreen, height: 1.6)),
                ),
                ..._events.map(_eventCard),
              ]),
            ),
    );
  }

  Widget _eventCard(dynamic e) {
    final members = e['members'] as List;
    final full = members.length >= e['cap'];
    final joined = e['joined'] == true;
    return Card(child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(e['title'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('${e['time']} · ${e['fee']} · L${e['minLevel']}+ · ${members.length}/${e['cap']}', style: const TextStyle(fontSize: 12, color: kGray)),
        const SizedBox(height: 10),
        Row(children: [
          ...members.take(6).map((m) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: avatar(m['nickname'] ?? '?', size: 26),
          )),
          const Spacer(),
          ElevatedButton(
            onPressed: (joined || full) ? null : () => _join(e['id']),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99))),
            child: Text(joined ? l.t('joined') : (full ? l.t('full') : l.t('join'))),
          ),
        ]),
      ]),
    ));
  }
}
