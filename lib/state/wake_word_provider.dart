import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/data/voice/wake_word.dart';
import 'package:stt_tts/state/settings_provider.dart';

const _picovoiceKey = String.fromEnvironment('PICOVOICE_KEY', defaultValue: '');

/// The singleton `WakeWordService`. Returns `null` when no AccessKey was
/// passed via `--dart-define=PICOVOICE_KEY=...` — callers should treat that
/// as "wake word not available on this build".
final wakeWordServiceProvider = Provider<WakeWordService?>((ref) {
  if (_picovoiceKey.isEmpty) return null;
  final s = WakeWordService(accessKey: _picovoiceKey);
  ref.onDispose(s.dispose);
  return s;
});

/// Tracks whether the wake-word listener is currently running and toggles it
/// based on (speechModeVisible AND settings.wakeWordEnabled).
class WakeWordController {
  WakeWordController(this._ref);
  final Ref _ref;
  bool _running = false;

  /// Call from VoiceHome's initState (`true`) and dispose (`false`).
  Future<void> sync({required bool speechModeVisible}) async {
    final svc = _ref.read(wakeWordServiceProvider);
    if (svc == null) return;
    final enabled = _ref.read(settingsProvider).wakeWordEnabled;
    final shouldRun = speechModeVisible && enabled;
    if (shouldRun && !_running) {
      _running = await svc.start();
    } else if (!shouldRun && _running) {
      await svc.stop();
      _running = false;
    }
  }
}

final wakeWordControllerProvider = Provider<WakeWordController>(
  (ref) => WakeWordController(ref),
);
