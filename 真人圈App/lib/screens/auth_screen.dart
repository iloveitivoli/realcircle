import 'package:flutter/material.dart';
import '../api.dart';
import '../i18n.dart';
import '../theme.dart';

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
  bool _busy = false;
  final l = L10n.instance;

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
                        TextField(controller: _phone, keyboardType: TextInputType.phone, maxLength: 11,
                            decoration: InputDecoration(hintText: l.t('phone'), counterText: '')),
                        const SizedBox(height: 10),
                        TextField(controller: _pwd, obscureText: true,
                            decoration: InputDecoration(hintText: l.t('pwd'))),
                        const SizedBox(height: 10),
                        TextField(controller: _nick, maxLength: 20,
                            decoration: InputDecoration(hintText: l.t('nick'), counterText: '')),
                        const SizedBox(height: 6),
                        SizedBox(width: double.infinity, child: ElevatedButton(
                          onPressed: _busy ? null : () => _run(() => Api.register(_phone.text, _pwd.text, _nick.text)),
                          child: Text(l.t('toReg')),
                        )),
                        const SizedBox(height: 8),
                        SizedBox(width: double.infinity, child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kGreen, side: const BorderSide(color: kGreen, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                          ),
                          onPressed: _busy ? null : () => _run(() => Api.login(_phone.text, _pwd.text)),
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
