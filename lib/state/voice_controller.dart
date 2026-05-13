import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/data/voice/stt_service.dart';
import 'package:stt_tts/data/voice/tts_service.dart';
import 'package:stt_tts/data/voice/voice_command_detector.dart';
import 'package:stt_tts/data/voice/voice_coordinator.dart';
import 'package:stt_tts/domain/markdown/strip_markdown.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/state/repositories_provider.dart';
import 'package:stt_tts/state/ui_mode_provider.dart';
import 'package:stt_tts/state/voice_provider.dart';

/// Provides the singleton STT service. Calls `init()` once.
final sttServiceProvider = Provider<SttService>((ref) {
  final s = SttService();
  // ignore: discarded_futures — fire-and-forget; surface errors via streams.
  s.init();
  ref.onDispose(s.dispose);
  return s;
});

/// Provides the singleton TTS service. Calls `init()` once.
final ttsServiceProvider = Provider<TtsService>((ref) {
  final t = TtsService();
  // ignore: discarded_futures
  t.init();
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

/// Orchestrates a single tap-to-talk turn for one session:
///
/// 1. Tap mic when idle → mutex stops TTS → STT starts → state.userStart()
/// 2. Final transcript arrives → state.gotFinalTranscript() →
///    `ChatRepository.send(sessionKey:, text:)`
/// 3. Watch the message stream for that session — when a new finalized
///    assistant message arrives, state.aiBeganSpeaking() and TTS reads its
///    plain-text-stripped body.
/// 4. TTS status returns to `idle` → state.aiDoneSpeaking().
/// 5. Tap mic during listening → STT stops, state.userStop().
/// 6. Tap mic during responding → TTS stops, state.interrupt().
class VoiceController {
  VoiceController(this._ref, this.sessionKey);

  final Ref _ref;
  final String sessionKey;

  /// Tracks the assistant message ids we've already spoken so we don't
  /// re-speak on every list update.
  final Set<String?> _spokenIds = <String?>{};

  /// True once we've absorbed the BehaviorSubject-style replay of the
  /// current message list on subscribe — any assistant messages present at
  /// that moment are added to [_spokenIds] without speaking. Without this,
  /// switching chat → voice → tap mic causes TTS to read the previous
  /// assistant reply that was already on screen.
  bool _replaySnapshotConsumed = false;
  StreamSubscription<List<Message>>? _messagesSub;
  StreamSubscription<SttTranscript>? _transcriptSub;
  StreamSubscription<TtsStatus>? _ttsStatusSub;

  /// Voice command detector — runs a low-priority STT loop during TTS
  /// playback to detect Stop/Repeat/Cancel keywords.
  /// This is the documented exception to the STT/TTS mutual-exclusion rule.
  final _detector = VoiceCommandDetector();
  StreamSubscription<VoiceCommand>? _detectorSub;

  /// The plain text most recently passed to tts.speak(), used to re-speak on
  /// a `repeat` voice command.
  String? _lastSpokenText;

  Future<void> tapMic() async {
    final state = _ref.read(voiceStateProvider.notifier);
    final stt = _ref.read(sttServiceProvider);
    final tts = _ref.read(ttsServiceProvider);
    final coord = _ref.read(voiceCoordinatorProvider);

    final current = _ref.read(voiceStateProvider);

    if (current == VoiceState.responding) {
      await tts.stop();
      state.interrupt();
      return;
    }
    if (current == VoiceState.listening) {
      await stt.stop();
      state.userStop();
      return;
    }

    // Begin a new turn.
    state.userStart();

    // Subscribe to the assistant message stream BEFORE listening starts so we
    // don't miss the reply if it arrives quickly. Re-subscriptions are no-op
    // safe because each subscription is gated on _spokenIds.
    _bindReplyListener();

    await coord.startListening(begin: () => stt.start());

    // One-shot: when a final transcript arrives, send it.
    await _transcriptSub?.cancel();
    _transcriptSub = stt.transcript.listen((t) async {
      if (!t.isFinal) return;
      await _transcriptSub?.cancel();
      _transcriptSub = null;
      state.gotFinalTranscript(t.text);
      try {
        await _ref.read(chatRepositoryProvider).send(
              sessionKey: sessionKey,
              text: t.text,
            );
      } catch (_) {
        // Send failed — drop back to idle so the user can retry.
        state.aiDoneSpeaking();
      }
    });
  }

  void _bindReplyListener() {
    if (_messagesSub != null) return;
    final coord = _ref.read(voiceCoordinatorProvider);
    final tts = _ref.read(ttsServiceProvider);
    final state = _ref.read(voiceStateProvider.notifier);
    final repo = _ref.read(chatRepositoryProvider);

    _messagesSub = repo.messages(sessionKey).listen((list) async {
      // First event after subscribe is a replay of the current list. Treat
      // every assistant message present as already-spoken so we don't read
      // back the previous reply when the user enters voice mode.
      if (!_replaySnapshotConsumed) {
        _replaySnapshotConsumed = true;
        for (final m in list) {
          if (m.role == Role.assistant &&
              m.streaming == StreamingState.finalized) {
            _spokenIds.add(m.openclawId ?? m.runId);
          }
        }
        return;
      }

      if (list.isEmpty) return;
      final last = list.last;
      if (last.role != Role.assistant) return;
      if (last.streaming != StreamingState.finalized) return;
      final msgKey = last.openclawId ?? last.runId;
      if (_spokenIds.contains(msgKey)) return;
      _spokenIds.add(msgKey);

      // Belt and suspenders: never auto-speak in chat mode. The mic in chat
      // mode is dictation only; TTS playback is a voice-mode feature.
      if (_ref.read(uiModeProvider) != UiMode.voice) return;

      final text = _plainText(last);
      if (text.isEmpty) return;

      _lastSpokenText = stripMarkdown(text);
      state.aiBeganSpeaking();
      await coord.speak(begin: () => tts.speak(_lastSpokenText!));
    });

    _ttsStatusSub ??= tts.status.listen((s) async {
      if (s == TtsStatus.speaking) {
        await _detector.start();
        await _detectorSub?.cancel();
        _detectorSub = _detector.events.listen((cmd) async {
          final ttsLocal = _ref.read(ttsServiceProvider);
          final stateLocal = _ref.read(voiceStateProvider.notifier);
          switch (cmd) {
            case VoiceCommand.stop:
              await ttsLocal.stop();
              stateLocal.interrupt();
            case VoiceCommand.cancel:
              // TODO(voice): also abort the in-flight ChatRepository request
              // once we hold a cancellable reference (run id / CancelToken).
              await ttsLocal.stop();
              stateLocal.interrupt();
            case VoiceCommand.repeat:
              if (_lastSpokenText != null) {
                await ttsLocal.speak(_lastSpokenText!);
              }
          }
        });
      } else if (s == TtsStatus.idle &&
          _ref.read(voiceStateProvider) == VoiceState.responding) {
        await _detector.stop();
        await _detectorSub?.cancel();
        _detectorSub = null;
        state.aiDoneSpeaking();
      }
    });
  }

  /// Renders a finalized assistant message back to plain text from its parts.
  String _plainText(Message m) {
    final buf = StringBuffer();
    for (final part in m.parts) {
      if (part is TextPart) {
        buf.write(part.text);
      }
    }
    return buf.toString();
  }

  void dispose() {
    _messagesSub?.cancel();
    _transcriptSub?.cancel();
    _ttsStatusSub?.cancel();
    _detectorSub?.cancel();
    // ignore: discarded_futures — fire-and-forget on dispose.
    _detector.stop();
  }
}

final voiceControllerProvider = Provider.family<VoiceController, String>(
  (ref, sessionKey) {
    final c = VoiceController(ref, sessionKey);
    ref.onDispose(c.dispose);
    return c;
  },
);
