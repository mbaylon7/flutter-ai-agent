import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/design_tokens.dart';

/// App-level theme mode. `system` follows the OS preference; `light` /
/// `dark` are explicit user overrides (matches the HTML's behaviour where
/// the toggle in Settings flips out of system tracking).
enum AppThemeMode { system, light, dark }

class _ThemeNotifier extends StateNotifier<AppThemeMode> {
  _ThemeNotifier() : super(AppThemeMode.system);

  void setMode(AppThemeMode mode) => state = mode;
  void toggleLightDark(Brightness platformBrightness) {
    final effective = state == AppThemeMode.system
        ? (platformBrightness == Brightness.dark
            ? AppThemeMode.dark
            : AppThemeMode.light)
        : state;
    state = effective == AppThemeMode.dark
        ? AppThemeMode.light
        : AppThemeMode.dark;
  }
}

final appThemeProvider =
    StateNotifierProvider<_ThemeNotifier, AppThemeMode>((_) => _ThemeNotifier());

/// Resolved tokens for the current theme. Watches both the user-selected
/// mode and the live platform brightness, so a user on `system` mode sees
/// the tokens flip automatically when the OS theme changes.
final tokensProvider = Provider<OcTokens>((ref) {
  final mode = ref.watch(appThemeProvider);
  final platform = ref.watch(platformBrightnessProvider);
  final effective = mode == AppThemeMode.system
      ? platform
      : (mode == AppThemeMode.dark ? Brightness.dark : Brightness.light);
  return effective == Brightness.dark ? OcTokens.dark : OcTokens.light;
});

/// Surfaces the current platform brightness as a Riverpod provider so
/// [tokensProvider] can stay reactive without each widget reading
/// `MediaQuery`.
final platformBrightnessProvider =
    StateProvider<Brightness>((_) => Brightness.dark);
