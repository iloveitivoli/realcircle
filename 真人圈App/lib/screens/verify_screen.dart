import 'dart:math';
import 'package:flutter/material.dart';
import '../api.dart';
import '../i18n.dart';
import '../theme.dart';

class VerifyScreen extends StatefulWidget {
  final VoidCallback onDone;
  const VerifyScreen({super.key, required this.onDone});
  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final l = L10n.instance;
  String _face = '🙂';
  bool _busy = false;

  Future<void> _liveness() async {
    setState(() { _busy = true; _face = '👁️'; });
    await Future.delayed(const Duration(milliseconds: 1300));
    setState(() => _face = '🔄');
    await Future.delayed(const Duration(milliseconds: 1300));
    try {
      // 模拟唯一面容特征;生产环境由活体 SDK 返回特征向量
      final sample = List.generate(4, (_) => Random().nextInt(1 << 30)).join('-');
      await Api.liveness(sample);
      setState(() => _face = '✅');
      if (mounted) toast(context, l.t('congrats'));
      await Future.delayed(const Duration(milliseconds: 900));
      widget.onDone();
    } catch (e) {
      setState(() { _face = '🙂'; _busy = false; });
      if (mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(l.t('liveTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(children: [for (var i = 1; i <= 4; i++) _lvl(i)]),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.t('liveTitle'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(l.t('liveDesc'), style: const TextStyle(fontSize: 12.5, color: kGray, height: 1.7)),
                const SizedBox(height: 16),
                Center(child: Container(
                  width: 150, height: 150,
                  decoration: BoxDecoration(
                    color: kGreenL, shape: BoxShape.circle,
                    border: Border.all(color: kGreen, width: 4, style: BorderStyle.solid),
                  ),
                  child: Center(child: Text(_face, style: const TextStyle(fontSize: 58))),
                )),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: _busy ? null : _liveness,
                  child: Text(l.t('liveStart')),
                )),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kGreen, side: const BorderSide(color: kGreen, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  onPressed: () { Api.logout(); widget.onDone(); },
                  child: Text(l.t('liveLater'), style: const TextStyle(fontWeight: FontWeight.bold)),
                )),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lvl(int i) {
    final cur = (Api.me?['level'] ?? 1) >= i;
    const names = {1: 'L1', 2: 'L2 活体', 3: 'L3 实名', 4: 'L4 面验'};
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: cur ? kGreenL : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cur ? kGreen : const Color(0xFFE8E8E6)),
        ),
        child: Text(names[i]!, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: cur ? kGreen : kGray, fontWeight: cur ? FontWeight.w800 : FontWeight.normal)),
      ),
    );
  }
}
