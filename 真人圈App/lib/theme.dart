import 'package:flutter/material.dart';

// 暖色编辑感配色(与 Web 端一致)
const kGreen = Color(0xFF0C6B4F);
const kGreenD = Color(0xFF084C38);
const kGreenL = Color(0xFFE8F1EA);
const kGold = Color(0xFFBF9B30);
const kInk = Color(0xFF1D1B16); // 暖墨
const kGray = Color(0xFF8D8576); // 暖灰
const kBg = Color(0xFFF6F1E6); // 暖纸张
const kCard = Color(0xFFFFFDF8); // 暖白卡片
const kLine = Color(0xFFECE3D3); // 暖描边

// 衬线展示字体回退栈(标题/Logo;设备无则优雅回退到系统默认)
const kSerifFallback = ['Songti SC', 'Source Han Serif SC', 'Noto Serif SC', 'serif'];

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: kBg,
    colorScheme: ColorScheme.fromSeed(seedColor: kGreen, primary: kGreen, surface: kCard),
    appBarTheme: const AppBarTheme(
      backgroundColor: kCard,
      foregroundColor: kInk,
      elevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(color: kInk, fontSize: 19, fontWeight: FontWeight.w800, fontFamilyFallback: kSerifFallback),
    ),
    // Card 样式在各 Card() 处单独设置,避免不同 Flutter 版本 CardTheme/CardThemeData 类型差异
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kLine),
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
    1: ['L1', Color(0xFFEFE9DC), Color(0xFF9A9182)],
    2: ['✓', kGreenL, kGreen],
    3: ['🪪', Color(0xFFFBF3DA), Color(0xFF9A7B12)],
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
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: size * 0.42, fontFamilyFallback: kSerifFallback)),
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
