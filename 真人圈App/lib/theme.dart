import 'package:flutter/material.dart';

const kGreen = Color(0xFF0B6E4F);
const kGreenD = Color(0xFF0A5C42);
const kGreenL = Color(0xFFE8F3EE);
const kGold = Color(0xFFC9A227);
const kInk = Color(0xFF16181C);
const kGray = Color(0xFF8A9099);
const kBg = Color(0xFFF3F4F3);

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: kBg,
    colorScheme: ColorScheme.fromSeed(seedColor: kGreen, primary: kGreen),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: kInk,
      elevation: 0.5,
      centerTitle: false,
    ),
    // Card 样式在各 Card() 处单独设置,避免不同 Flutter 版本 CardTheme/CardThemeData 类型差异
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE8E8E6)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE8E8E6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kGreen, width: 1.5),
      ),
    ),
  );
}

/// 真人验证等级徽章
Widget levelBadge(int level) {
  const map = {
    1: ['L1', Color(0xFFEEEEEE), Color(0xFF888888)],
    2: ['✓', kGreenL, kGreen],
    3: ['🪪', Color(0xFFFFF6DC), Color(0xFF9A7B12)],
    4: ['⭐', kInk, kGold],
  };
  final m = map[level] ?? map[1]!;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: m[1] as Color, borderRadius: BorderRadius.circular(99)),
    child: Text(m[0] as String, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: m[2] as Color)),
  );
}

Color avatarColor(String name) {
  const cs = [Color(0xFF5B8DEF), Color(0xFFE8956B), Color(0xFF9B7EDE), Color(0xFF4EA8A0), Color(0xFFD6708B), kGold, kGreen];
  int h = 0;
  for (final c in name.runes) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return cs[h % cs.length];
}

Widget avatar(String name, {double size = 40}) {
  final n = name.isEmpty ? '?' : name;
  return CircleAvatar(
    radius: size / 2,
    backgroundColor: avatarColor(n),
    child: Text(n.characters.first,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: size * 0.42)),
  );
}

void toast(BuildContext c, String msg) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    backgroundColor: kInk,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
    duration: const Duration(seconds: 2),
  ));
}

String timeAgo(int ts) {
  final s = (DateTime.now().millisecondsSinceEpoch - ts) / 1000;
  if (s < 60) return 'now';
  if (s < 3600) return '${(s / 60).floor()}m';
  if (s < 86400) return '${(s / 3600).floor()}h';
  return '${(s / 86400).floor()}d';
}
