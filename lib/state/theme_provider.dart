import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/design_tokens.dart';
import 'package:stt_tts/data/secure/secure_store.dart';
import 'package:stt_tts/state/connection_provider.dart';

/// App-level theme mode. `system` follows the OS preference; `light` /
/// `dark` are explicit user overrides.
enum AppThemeMode { system, light, dark }

class _ThemeNotifier extends StateNotifier<AppThemeMode> {
  _ThemeNotifier(this._store) : super(AppThemeMode.system) {
    // Restore the persisted choice asynchronously — if the user picked a
    // theme in a previous session, we flip to it once the secure store
    // returns. Default stays `system` until the read completes.
    _restore();
  }

  static const _storeKey = 'oc.themeMode';
  final SecureStore _store;

  Future<void> _restore() async {
    try {
      final raw = await _store.read(_storeKey);
      if (raw == null) return;
      final restored = AppThemeMode.values.firstWhere(
        (m) => m.name == raw,
        orElse: () => AppThemeMode.system,
      );
      if (mounted) state = restored;
    } catch (_) {
      // Read failures fall back to the default mode — not worth surfacing.
    }
  }

  void setMode(AppThemeMode mode) {
    state = mode;
    // Persist; failures don't block the in-memory state change.
    // ignore: discarded_futures
    _store.write(_storeKey, mode.name);
  }

  void toggleLightDark(Brightness platformBrightness) {
    final effective = state == AppThemeMode.system
        ? (platformBrightness == Brightness.dark
            ? AppThemeMode.dark
            : AppThemeMode.light)
        : state;
    final next = effective == AppThemeMode.dark
        ? AppThemeMode.light
        : AppThemeMode.dark;
    setMode(next);
  }
}

final appThemeProvider =
    StateNotifierProvider<_ThemeNotifier, AppThemeMode>((ref) {
  return _ThemeNotifier(ref.read(secureStoreProvider));
});

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
