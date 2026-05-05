import 'package:flutter/material.dart';

class OcColors {
  static const bgTop = Color(0xFFFFFFFF);
  static const bgBottom = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF4F4F5);
  static const accent = Color(0xFF111111);
  static const accent2 = Color(0xFF4B4B4B);
  static const textPrimary = Color(0xFF111111);
  static const textBody = Color(0xFF1F1F23);
  static const textSubtitle = Color(0xFF6B7280);
  static const textMeta = Color(0xFF9AA0A6);
  static const live = Color(0xFF1FAB6A);
  static const warn = Color(0xFFB36B00);
  static const danger = Color(0xFFDC2626);
  static const overlayTint = Color(0xFFF4F4F5);
  static const borderTint = Color(0xFFE5E7EB);
}

ThemeData ocLightTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: OcColors.bgBottom,
    colorScheme: ColorScheme.fromSeed(
      seedColor: OcColors.accent,
      brightness: Brightness.light,
      surface: OcColors.surface,
      primary: OcColors.accent,
      secondary: OcColors.accent2,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: OcColors.surface,
      foregroundColor: OcColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
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
