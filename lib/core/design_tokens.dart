import 'package:flutter/material.dart';

/// Design tokens ported 1:1 from `design/voice-app.html`'s `:root` and
/// `:root[data-theme="light"]` CSS variable blocks.
///
/// All token values come straight from the spec; do **not** invent shades
/// or alpha values that aren't in the design system.
///
/// Consume via `ref.watch(tokensProvider)` (see `lib/state/theme_provider.dart`).
@immutable
class OcTokens {
  const OcTokens({
    required this.bg,
    required this.silhouette,
    required this.silhouetteOpacity,
    required this.text,
    required this.textMuted,
    required this.textSoft,
    required this.accent,
    required this.surface,
    required this.surfaceActive,
    required this.border,
    required this.toggleOn,
    required this.micBg,
    required this.micBgActive,
    required this.micBorder,
    required this.micBorderActive,
    required this.micIcon,
    required this.micIconActive,
    required this.chipBg,
    required this.chipBgHover,
    required this.chipBorder,
    required this.chipIcon,
    required this.toastBg,
    required this.toastText,
    required this.toastBorder,
    required this.drawerBg,
    required this.brightness,
  });

  // ─── Surface / silhouette ───────────────────────────────────────────
  final Color bg;
  final Color silhouette;
  final double silhouetteOpacity;

  // ─── Text ─────────────────────────────────────────────────────────
  final Color text;
  final Color textMuted;
  final Color textSoft;
  final Color accent;

  // ─── Generic surfaces ────────────────────────────────────────────
  final Color surface;
  final Color surfaceActive;
  final Color border;

  // ─── Toggles ─────────────────────────────────────────────────────
  final Color toggleOn;

  // ─── Mic button ──────────────────────────────────────────────────
  final Color micBg;
  final Color micBgActive;
  final Color micBorder;
  final Color micBorderActive;
  final Color micIcon;
  final Color micIconActive;

  // ─── Chips ───────────────────────────────────────────────────────
  final Color chipBg;
  final Color chipBgHover;
  final Color chipBorder;
  final Color chipIcon;

  // ─── Toast ────────────────────────────────────────────────────────
  final Color toastBg;
  final Color toastText;
  final Color toastBorder;

  // ─── Drawer ──────────────────────────────────────────────────────
  final Color drawerBg;

  /// Underlying brightness — useful when widgets need to fork on theme
  /// (e.g. SVG asset selection, system status-bar tint).
  final Brightness brightness;

  // ─── Dark theme (default) ───────────────────────────────────────
  static const dark = OcTokens(
    bg: Color(0xFF000000),
    silhouette: Color(0xFF000000),
    silhouetteOpacity: 0.86,
    text: Color.fromRGBO(255, 255, 255, 0.94),
    textMuted: Color.fromRGBO(255, 255, 255, 0.42),
    textSoft: Color.fromRGBO(255, 255, 255, 0.66),
    accent: Color.fromRGBO(110, 170, 255, 1.0),
    surface: Color.fromRGBO(255, 255, 255, 0.05),
    surfaceActive: Color.fromRGBO(255, 255, 255, 0.10),
    border: Color.fromRGBO(255, 255, 255, 0.09),
    toggleOn: Color.fromRGBO(48, 200, 96, 1.0),
    micBg: Color.fromRGBO(255, 255, 255, 0.08),
    micBgActive: Color.fromRGBO(255, 255, 255, 0.18),
    micBorder: Color.fromRGBO(255, 255, 255, 0.16),
    micBorderActive: Color.fromRGBO(255, 255, 255, 0.4),
    micIcon: Color.fromRGBO(255, 255, 255, 0.9),
    micIconActive: Color.fromRGBO(255, 255, 255, 1.0),
    chipBg: Color.fromRGBO(255, 255, 255, 0.06),
    chipBgHover: Color.fromRGBO(255, 255, 255, 0.12),
    chipBorder: Color.fromRGBO(255, 255, 255, 0.12),
    chipIcon: Color.fromRGBO(255, 255, 255, 0.75),
    toastBg: Color.fromRGBO(30, 30, 30, 0.92),
    toastText: Color.fromRGBO(255, 255, 255, 0.96),
    toastBorder: Color.fromRGBO(255, 255, 255, 0.08),
    drawerBg: Color(0xFF1C1C1C),
    brightness: Brightness.dark,
  );

  // ─── Light theme ──────────────────────────────────────────────────
  static const light = OcTokens(
    bg: Color(0xFFF5F5F7),
    silhouette: Color(0xFFF5F5F7),
    silhouetteOpacity: 0.88,
    text: Color.fromRGBO(0, 0, 0, 0.86),
    textMuted: Color.fromRGBO(0, 0, 0, 0.45),
    textSoft: Color.fromRGBO(0, 0, 0, 0.6),
    accent: Color.fromRGBO(20, 100, 220, 1.0),
    surface: Color.fromRGBO(0, 0, 0, 0.035),
    surfaceActive: Color.fromRGBO(0, 0, 0, 0.07),
    border: Color.fromRGBO(0, 0, 0, 0.08),
    toggleOn: Color.fromRGBO(48, 200, 96, 1.0),
    micBg: Color.fromRGBO(0, 0, 0, 0.04),
    micBgActive: Color.fromRGBO(0, 0, 0, 0.10),
    micBorder: Color.fromRGBO(0, 0, 0, 0.12),
    micBorderActive: Color.fromRGBO(0, 0, 0, 0.32),
    micIcon: Color.fromRGBO(0, 0, 0, 0.7),
    micIconActive: Color.fromRGBO(0, 0, 0, 0.92),
    chipBg: Color.fromRGBO(0, 0, 0, 0.04),
    chipBgHover: Color.fromRGBO(0, 0, 0, 0.09),
    chipBorder: Color.fromRGBO(0, 0, 0, 0.10),
    chipIcon: Color.fromRGBO(0, 0, 0, 0.7),
    toastBg: Color.fromRGBO(40, 40, 40, 0.94),
    toastText: Color.fromRGBO(255, 255, 255, 0.96),
    toastBorder: Color.fromRGBO(255, 255, 255, 0.08),
    drawerBg: Color(0xFFF5F5F7),
    brightness: Brightness.light,
  );
}

/// App-level layout constants. Pixel offsets and sizes from the HTML.
class OcLayout {
  OcLayout._();

  /// Position of the controls row from the bottom of the screen.
  static const double controlsBottom = 32;

  /// Gap between the three control buttons.
  static const double controlsGap = 36;

  // 90 % of the original 76 / 44 / 22 / 28 design sizes.
  static const double micSize = 68; // 76 × 0.9
  static const double iconBtnSize = 40; // 44 × 0.9
  static const double micIconSize = 25; // 28 × 0.9
  static const double smallIconSize = 20; // 22 × 0.9

  /// Settings gear in the bottom action row.
  static const double gearIconSize = 20;

  /// Chat input pinned distance from the bottom — scales with the 68-px
  /// mic at 32-px bottom inset (mic top sits ~100 px from bottom).
  static const double chatInputBottom = 127;

  /// Toast pinned distance from the bottom.
  static const double toastBottom = 119;

  /// Chat stage: top inset (from safe area) and bottom inset.
  ///
  /// `chatStageBottom` is generous on purpose — the wave's glow halo reaches
  /// well above the wave baseline, so the conversation list must end above
  /// it to keep text readable. Pushed lower now that the wave-stage starts
  /// at 60 % (was 50 %) of the screen.
  static const double chatStageTop = 12;
  static const double chatStageBottom = 180;
}
