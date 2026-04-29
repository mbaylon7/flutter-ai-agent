import 'package:flutter/material.dart';

class OcColors {
  static const bgTop = Color(0xFF1c2a4a);
  static const bgBottom = Color(0xFF0a0e1a);
  static const surface = Color(0xFF0E1424);
  static const accent = Color(0xFF6CB0FF);
  static const accent2 = Color(0xFF8A7AFF);
  static const textPrimary = Color(0xFFE8EEFF);
  static const textBody = Color(0xFFD6E2FF);
  static const textSubtitle = Color(0xFF8AA3D4);
  static const textMeta = Color(0xFF5A6886);
  static const live = Color(0xFF5CD99A);
  static const warn = Color(0xFFFFB86C);
  static const danger = Color(0xFFFF7A85);
  static const overlayTint = Color(0x0F78B4FF);
  static const borderTint = Color(0x2978B4FF);
}

ThemeData ocDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: OcColors.bgBottom,
    colorScheme: ColorScheme.fromSeed(
      seedColor: OcColors.accent,
      brightness: Brightness.dark,
      surface: OcColors.surface,
      primary: OcColors.accent,
      secondary: OcColors.accent2,
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        color: OcColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: OcColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(color: OcColors.textBody),
      bodyMedium: TextStyle(color: OcColors.textBody),
      bodySmall: TextStyle(color: OcColors.textSubtitle),
      labelSmall: TextStyle(color: OcColors.textMeta, fontSize: 10),
    ),
  );
}

const ocBackgroundGradient = LinearGradient(
  begin: Alignment(0, -1),
  end: Alignment(0, 0.6),
  colors: [OcColors.bgTop, OcColors.bgBottom],
);
