import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/data/voice/stt_service.dart';
import 'package:stt_tts/data/voice/tts_service.dart';
import 'package:stt_tts/data/voice/voice_coordinator.dart';
import 'package:stt_tts/state/settings_provider.dart';

/// Provides the singleton STT service. Calls `init()` once.
final sttServiceProvider = Provider<SttService>((ref) {
  final s = SttService();
  // ignore: discarded_futures — fire-and-forget; surface errors via streams.
  s.init();
  ref.onDispose(s.dispose);
  return s;
});

/// Provides the singleton TTS service. Calls `init()` once and reapplies
/// the persisted voice key from settings whenever it changes.
final ttsServiceProvider = Provider<TtsService>((ref) {
  final t = TtsService();
  // ignore: discarded_futures
  t.init();
  // Reapply persisted voice on launch + any subsequent change.
  ref.listen<String?>(
    settingsProvider.select((s) => s.voiceKey),
    (_, next) {
      if (next != null && next.isNotEmpty) {
        // ignore: discarded_futures
        t.selectVoice(next);
      }
    },
    fireImmediately: true,
  );
  ref.onDispose(t.dispose);
  return t;
});

/// Provides the mutex coordinator wired to the live STT/TTS services.
final voiceCoordinatorProvider = Provider<VoiceCoordinator>((ref) {
  final stt = ref.watch(sttServiceProvider);
  final tts = ref.watch(ttsServiceProvider);
  return VoiceCoordinator(
    stopTts: () => tts.stop(),
    stopStt: () => stt.stop(),
  );
});
