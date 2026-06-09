import 'dart:async';
import 'package:flutter/material.dart';
import '../api.dart';
import '../i18n.dart';
import '../theme.dart';

const kDialCodes = [
  ['86', '🇨🇳 +86'], ['852', '🇭🇰 +852'], ['886', '🇹🇼 +886'], ['971', '🇦🇪 +971'],
  ['1', '🇺🇸 +1'], ['44', '🇬🇧 +44'], ['65', '🇸🇬 +65'], ['81', '🇯🇵 +81'],
  ['82', '🇰🇷 +82'], ['66', '🇹🇭 +66'], ['84', '🇻🇳 +84'], ['60', '🇲🇾 +60'],
  ['62', '🇮🇩 +62'], ['91', '🇮🇳 +91'], ['61', '🇦🇺 +61'], ['966', '🇸🇦 +966'],
];

class AuthScreen extends StatefulWidget {
  final VoidCallback onDone;
  const AuthScreen({super.key, required this.onDone});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phone = TextEditingController();
  final _pwd = TextEditingController();
  final _nick = TextEditingController();
  final _code = TextEditingController();
  String _dial = '86';
  int _cd = 0; // 验证码倒计时
  Timer? _cdTimer;
  bool _busy = false;
  final l = L10n.instance;

  String _tx(String zh, String en, String ar) => l.lang == 'en' ? en : (l.lang == 'ar' ? ar : zh);

  @override
  void dispose() {
    _cdTimer?.cancel();
    _phone.dispose(); _pwd.dispose(); _nick.dispose(); _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_phone.text.trim().isEmpty) { toast(context, l.t('phone')); return; }
    try {
      final code = await Api.sendSms(_dial, _phone.text.trim());
      if (code != null) { _code.text = code; if (mounted) toast(context, '${_tx('演示验证码', 'Demo code', 'رمز تجريبي')}: $code'); }
      else if (mounted) toast(context, _tx('验证码已发送', 'Code sent', 'تم الإرسال'));
      setState(() => _cd = 60);
      _cdTimer?.cancel();
      _cdTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_cd <= 1) { t.cancel(); if (mounted) setState(() => _cd = 0); }
        else if (mounted) setState(() => _cd--);
      });
    } catch (e) { if (mounted) toast(context, _errText(e)); }
  }

  String _errText(Object e) =>
      (e is ApiException && e.code == 'AI_BLOCKED') ? l.t('aiblocked') : e.toString();

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
      widget.onDone();
    } catch (e) {
      if (mounted) toast(context, _errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [kGreen, kGreenD]),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🤝', style: TextStyle(fontSize: 50)),
                  const SizedBox(height: 6),
                  Text('真人圈 RealCircle',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(l.t('sub'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 18),
                  _langPicker(),
                  const SizedBox(height: 18),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(children: [
                        Row(children: [
                          DropdownButton<String>(
                            value: _dial,
                            underline: const SizedBox(),
                            items: kDialCodes.map((c) => DropdownMenuItem(value: c[0], child: Text(c[1], style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                            onChanged: (v) => setState(() => _dial = v ?? '86'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: TextField(controller: _phone, keyboardType: TextInputType.phone, maxLength: 14,
                              decoration: InputDecoration(hintText: l.t('phone'), counterText: ''))),
                        ]),
                        const SizedBox(height: 10),
                        TextField(controller: _pwd, obscureText: true,
                            decoration: InputDecoration(hintText: l.t('pwd'))),
                        const SizedBox(height: 10),
                        TextField(controller: _nick, maxLength: 20,
                            decoration: InputDecoration(hintText: l.t('nick'), counterText: '')),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: TextField(controller: _code, keyboardType: TextInputType.number, maxLength: 6,
                              decoration: InputDecoration(hintText: _tx('短信验证码', 'SMS code', 'رمز التحقق'), counterText: ''))),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: (_busy || _cd > 0) ? null : _sendCode,
                            child: Text(_cd > 0 ? '${_cd}s' : _tx('获取验证码', 'Get code', 'إرسال الرمز')),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        SizedBox(width: double.infinity, child: ElevatedButton(
                          onPressed: _busy ? null : () => _run(() => Api.register(_phone.text.trim(), _pwd.text, _nick.text, dial: _dial, code: _code.text.trim())),
                          child: Text(l.t('toReg')),
                        )),
                        const SizedBox(height: 8),
                        SizedBox(width: double.infinity, child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kGreen, side: const BorderSide(color: kGreen, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                          ),
                          onPressed: _busy ? null : () => _run(() => Api.login(_phone.text.trim(), _pwd.text, dial: _dial)),
                          child: Text(l.t('have'), style: const TextStyle(fontWeight: FontWeight.bold)),
                        )),
                        const SizedBox(height: 10),
                        Text(l.t('agree'), style: const TextStyle(fontSize: 11, color: kGray, height: 1.6)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _langPicker() {
    const labels = {'zh': '中文', 'en': 'English', 'ar': 'عربي'};
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: labels.entries.map((e) {
        final on = l.lang == e.key;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GestureDetector(
            onTap: () => l.set(e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: on ? kGold : Colors.white24,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: on ? kGold : Colors.white38),
              ),
              child: Text(e.value,
                  style: TextStyle(
                      color: on ? kInk : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
          ),
        );
      }).toList(),
    );
  }
}
