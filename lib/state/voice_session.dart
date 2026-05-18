import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/data/voice/stt_service.dart';
import 'package:stt_tts/data/voice/tts_service.dart';
import 'package:stt_tts/domain/markdown/strip_markdown.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/domain/voice/sentence_chunker.dart';
import 'package:stt_tts/state/repositories_provider.dart';
import 'package:stt_tts/state/ui_mode_provider.dart';
import 'package:stt_tts/state/voice_controller.dart';
import 'package:stt_tts/state/voice_provider.dart';

/// Orchestrates a continuous Gemini-Live-style conversation for one session.
///
/// AI playback (TTS + word-by-word captions) runs regardless of UI mode —
/// every new assistant reply is spoken in both chat and voice mode. STT
/// listening is voice-mode-only and is toggled via [startListening] /
/// [stopListening] by the shell on mode flips.
///
/// State machine (owned by [voiceStateProvider]):
///
/// ```
///                 startListening()
///   idle ───────────────────────────►  listening
///                                  │
///         user starts speaking     │
///   listening ◄──────────────► userSpeaking
///                                  │
///         end-of-turn (final transcript)
///                                  ▼
///                              processing
///                                  │
///                          first assistant delta
///                                  ▼
///                              aiSpeaking
///                                  │
///                  TTS queue drains + reply finalized
///                                  ▼
///                              listening
/// ```
class VoiceSession {
  VoiceSession(this._ref, this.sessionKey);

  final Ref _ref;
  final String sessionKey;

  static const _chunker = SentenceChunker();

  // STT pipeline.
  StreamSubscription<SttTranscript>? _transcriptSub;
  Timer? _silenceTimer;
  // How long the user can pause mid-thought before we treat the turn as
  // finished. Vosk's own endpointing fires after ~300ms of silence — way
  // too aggressive for natural speech ("hello… what's the weather today"
  // would otherwise commit as two separate messages). We ignore Vosk's
  // "final" flag for end-of-turn detection and rely on this timer instead.
  static const _silenceTimeout = Duration(milliseconds: 1500);

  // Accumulated text for the current user turn. Vosk fires `isFinal: true`
  // after every short pause, so we concatenate those finals locally and
  // only commit when [_silenceTimeout] elapses with no new audio.
  final StringBuffer _turnBuffer = StringBuffer();
  String _lastPartial = '';

  // Assistant message stream + TTS chunker.
  StreamSubscription<List<Message>>? _messagesSub;
  bool _messagesReplayConsumed = false;
  final Set<String?> _knownAssistantIds = <String?>{};
  String? _activeAssistantKey;
  int _chunkCursor = 0;
  bool _ttsActive = false;

  // Word-by-word subtitle: track what TTS has finished speaking and what it
  // is currently saying, so [liveAiTranscriptProvider] reveals one word at
  // a time in sync with the audio.
  StreamSubscription<TtsProgress>? _ttsProgressSub;
  StreamSubscription<TtsStatus>? _ttsStatusSub;
  final List<String> _spokenChunks = [];
  String _currentChunkText = '';

  bool _disposed = false;

  /// Always-on hooks: assistant message stream + TTS progress tracking. Safe
  /// to call repeatedly; subsequent calls are no-ops.
  void enable() {
    if (_disposed) return;
    _bindMessageStream();
    _bindTtsProgress();
  }

  /// Begin (or resume) continuous STT listening. Voice-mode-only entry point.
  ///
  /// `SttService.init()` is fire-and-forget — on cold launch the post-frame
  /// callback that triggers this method usually beats the platform-side
  /// permission/init handshake, so `stt.isAvailable` is still false and the
  /// underlying `listen` call no-ops. We retry every 250 ms (up to ~3 s) so
  /// the mic comes up automatically as soon as STT is ready, without the
  /// user needing to toggle modes to nudge it.
  Future<void> startListening() async {
    if (_disposed) return;
    enable();

    final stt = _ref.read(sttServiceProvider);
    if (!stt.isAvailable) {
      _scheduleStartRetry();
      return;
    }

    final current = _ref.read(voiceStateProvider);
    if (current == VoiceState.listening ||
        current == VoiceState.userSpeaking ||
        current == VoiceState.processing ||
        current == VoiceState.aiSpeaking) {
      return;
    }

    _bindTranscriptStream();
    _ref.read(voiceStateProvider.notifier).set(VoiceState.listening);
    final coord = _ref.read(voiceCoordinatorProvider);
    await coord.startListening(begin: () => stt.startContinuous());
  }

  int _startRetries = 0;
  static const _maxStartRetries = 12; // ≈ 3 s at 250 ms apart

  void _scheduleStartRetry() {
    if (_startRetries >= _maxStartRetries) return;
    _startRetries++;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (_disposed) return;
      // Only retry while we're meant to be in voice mode.
      if (_ref.read(uiModeProvider) != UiMode.voice) {
        _startRetries = 0;
        return;
      }
      startListening().whenComplete(() {
        if (_ref.read(sttServiceProvider).isAvailable) _startRetries = 0;
      });
    });
  }

  /// Stop STT listening without tearing down the AI playback path. Used when
  /// the shell flips to chat mode — replies still arrive via the keyboard
  /// and the AI still speaks; only the mic is closed.
  Future<void> stopListening() async {
    _silenceTimer?.cancel();
    final stt = _ref.read(sttServiceProvider);
    await stt.stop();
    final current = _ref.read(voiceStateProvider);
    // Always demote to `paused` when the shell tells us to stop listening,
    // including mid-`aiSpeaking`. Otherwise a chat-mode flip during TTS
    // leaves the state at aiSpeaking, and the next startListening() bails
    // because its no-op guard sees aiSpeaking and assumes the mic is hot.
    if (current != VoiceState.idle && current != VoiceState.paused) {
      _ref.read(voiceStateProvider.notifier).set(VoiceState.paused);
      _ref.read(liveUserTranscriptProvider.notifier).state = '';
    }
  }

  /// Legacy alias for the old in-voice-mode toggle behaviour.
  Future<void> start() => startListening();
  Future<void> pause() => stopListening();

  /// Fully end the session and release resources.
  Future<void> stop() async {
    await stopListening();
    final tts = _ref.read(ttsServiceProvider);
    await tts.clearQueue();
    _ttsActive = false;
    await _transcriptSub?.cancel();
    _transcriptSub = null;
    await _messagesSub?.cancel();
    _messagesSub = null;
    await _ttsProgressSub?.cancel();
    _ttsProgressSub = null;
    await _ttsStatusSub?.cancel();
    _ttsStatusSub = null;
    _messagesReplayConsumed = false;
    _spokenChunks.clear();
    _currentChunkText = '';
    _ref.read(voiceStateProvider.notifier).set(VoiceState.idle);
    _ref.read(liveUserTranscriptProvider.notifier).state = '';
    _ref.read(liveAiTranscriptProvider.notifier).state = '';
  }

  void dispose() {
    _disposed = true;
    _silenceTimer?.cancel();
    _transcriptSub?.cancel();
    _messagesSub?.cancel();
    _ttsProgressSub?.cancel();
    _ttsStatusSub?.cancel();
  }

  // --- STT pipeline ----------------------------------------------------

  void _bindTranscriptStream() {
    if (_transcriptSub != null) return;
    final stt = _ref.read(sttServiceProvider);
    _transcriptSub = stt.transcript.listen(_handleTranscript);
  }

  Future<void> _handleTranscript(SttTranscript t) async {
    if (_disposed) return;
    if (_ref.read(uiModeProvider) != UiMode.voice) return;

    final text = t.text.trim();
    if (text.isEmpty) return;

    final stateNotifier = _ref.read(voiceStateProvider.notifier);
    final current = _ref.read(voiceStateProvider);

    // Ignore any transcripts that arrive while the AI is talking — that's
    // the AI's own voice bleeding into the mic from the speaker. The mic is
    // paused at TTS start and resumed at TTS end (see _ensureTtsActive /
    // _handleTtsStatus), but in-flight final results can still land here.
    if (current == VoiceState.aiSpeaking) return;

    // Vosk fires `isFinal: true` after every ~300ms of silence even
    // mid-sentence. We accumulate those finals into [_turnBuffer] and treat
    // the partial as an in-flight tail; the actual turn commit happens only
    // when [_silenceTimeout] elapses with no further audio (see
    // [_forceEndOfTurn]).
    if (t.isFinal) {
      if (_turnBuffer.isNotEmpty) _turnBuffer.write(' ');
      _turnBuffer.write(text);
      _lastPartial = '';
    } else {
      _lastPartial = text;
    }

    final liveText = _composeLiveText();
    _ref.read(liveUserTranscriptProvider.notifier).state = liveText;

    if (current == VoiceState.listening ||
        current == VoiceState.processing) {
      stateNotifier.set(VoiceState.userSpeaking);
    }

    _silenceTimer?.cancel();
    _silenceTimer = Timer(_silenceTimeout, _forceEndOfTurn);
  }

  String _composeLiveText() {
    if (_turnBuffer.isEmpty) return _lastPartial;
    if (_lastPartial.isEmpty) return _turnBuffer.toString();
    return '${_turnBuffer.toString()} $_lastPartial';
  }

  Future<void> _forceEndOfTurn() async {
    if (_disposed) return;
    final current = _ref.read(voiceStateProvider);
    if (current != VoiceState.userSpeaking) return;
    final text = _composeLiveText().trim();
    if (text.isEmpty) return;
    _silenceTimer?.cancel();
    await _commitTurn(text);
  }

  Future<void> _commitTurn(String text) async {
    if (_disposed) return;
    _turnBuffer.clear();
    _lastPartial = '';
    _ref.read(voiceStateProvider.notifier).set(VoiceState.processing);
    _ref.read(liveUserTranscriptProvider.notifier).state = '';
    _ref.read(liveAiTranscriptProvider.notifier).state = '';

    // Phase 1: bypass the LLM/gateway entirely. Echo the user transcript
    // straight back via the chat repository, which inserts both the user
    // and a finalized assistant message — the existing message stream
    // pipeline then routes the echo through the TTS chunker just like a
    // real AI reply would.
    try {
      await _ref.read(chatRepositoryProvider).sendEcho(
            sessionKey: sessionKey,
            text: text,
          );
    } catch (_) {
      _ref.read(voiceStateProvider.notifier).set(VoiceState.listening);
    }
  }

  // --- Assistant streaming + TTS chunker -------------------------------

  void _bindMessageStream() {
    if (_messagesSub != null) return;
    final repo = _ref.read(chatRepositoryProvider);
    _messagesSub = repo.messages(sessionKey).listen(_handleMessages);
  }

  Future<void> _handleMessages(List<Message> list) async {
    if (_disposed) return;

    // First event is a replay of the current list — record all existing
    // assistant ids so historical messages don't get re-spoken.
    if (!_messagesReplayConsumed) {
      _messagesReplayConsumed = true;
      for (final m in list) {
        if (m.role == Role.assistant) {
          _knownAssistantIds.add(_idFor(m));
        }
      }
      return;
    }

    if (list.isEmpty) return;

    Message? current;
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].role == Role.assistant) {
        current = list[i];
        break;
      }
    }
    if (current == null) return;

    final id = _idFor(current);

    // New assistant turn — reset cursor and clear last reply's subtitle.
    if (id != _activeAssistantKey) {
      _activeAssistantKey = id;
      _chunkCursor = 0;
      _knownAssistantIds.add(id);
      _spokenChunks.clear();
      _currentChunkText = '';
      _ref.read(liveAiTranscriptProvider.notifier).state = '';
    }

    final plain = stripMarkdown(_plain(current));
    final result = _chunker.drainSentences(
      plain,
      _chunkCursor,
      forceFlush: current.streaming == StreamingState.finalized,
    );
    _chunkCursor = result.cursor;

    if (result.chunks.isNotEmpty) {
      await _ensureTtsActive();
      final tts = _ref.read(ttsServiceProvider);
      for (final chunk in result.chunks) {
        unawaited(tts.enqueueChunk(chunk));
      }
    }

    if (current.streaming == StreamingState.finalized) {
      await _finishAssistantTurn();
    }
  }

  Future<void> _ensureTtsActive() async {
    if (_ttsActive) return;
    _ttsActive = true;
    _ref.read(voiceStateProvider.notifier).set(VoiceState.aiSpeaking);
    // Pause the mic so the AI's own voice through the speaker doesn't get
    // picked up as user input. Auto-resumes in _finishAssistantTurn.
    final stt = _ref.read(sttServiceProvider);
    await stt.stop();
    _silenceTimer?.cancel();
    _ref.read(liveUserTranscriptProvider.notifier).state = '';
  }

  Future<void> _finishAssistantTurn() async {
    final tts = _ref.read(ttsServiceProvider);
    await tts.awaitDrained();
    if (_disposed) return;

    // Flush any in-flight "currently speaking" chunk to the spoken history
    // so the final subtitle equals the full reply.
    if (_currentChunkText.isNotEmpty) {
      _spokenChunks.add(_currentChunkText);
      _currentChunkText = '';
      _ref.read(liveAiTranscriptProvider.notifier).state =
          _spokenChunks.join(' ');
    }

    _ttsActive = false;
    _activeAssistantKey = null;
    _chunkCursor = 0;

    // Resume the mic now that the speaker is quiet.
    if (_ref.read(uiModeProvider) != UiMode.voice) {
      // Reset state so a later voice-mode re-entry can restart the mic.
      // Without this, state stays at aiSpeaking and startListening() no-ops.
      final s = _ref.read(voiceStateProvider);
      if (s != VoiceState.idle && s != VoiceState.paused) {
        _ref.read(voiceStateProvider.notifier).set(VoiceState.paused);
      }
      return;
    }
    final state = _ref.read(voiceStateProvider);
    if (state == VoiceState.idle || state == VoiceState.paused) return;

    _ref.read(voiceStateProvider.notifier).set(VoiceState.listening);
    final stt = _ref.read(sttServiceProvider);
    await _ref.read(voiceCoordinatorProvider).startListening(
          begin: () => stt.startContinuous(),
        );
  }

  // --- TTS progress (word-by-word subtitle sync) -----------------------

  void _bindTtsProgress() {
    if (_ttsProgressSub != null) return;
    final tts = _ref.read(ttsServiceProvider);
    _ttsProgressSub = tts.progress.listen(_handleTtsProgress);
    _ttsStatusSub = tts.status.listen(_handleTtsStatus);
  }

  void _handleTtsProgress(TtsProgress p) {
    if (_disposed) return;
    // Show the entire chunk text up front so the subtitle never freezes
    // mid-message between TTS chunks (the previous reveal-as-spoken approach
    // looked like "AI is done" during the pause between sentences). The
    // current word position is still emitted in TtsProgress for a future
    // highlight cursor — for Phase 1 we just render the full text.
    if (p.text != _currentChunkText) {
      if (_currentChunkText.isNotEmpty) {
        _spokenChunks.add(_currentChunkText);
      }
      _currentChunkText = p.text;
    }
    final subtitle = [..._spokenChunks, p.text].join(' ').trim();
    _ref.read(liveAiTranscriptProvider.notifier).state = subtitle;
  }

  void _handleTtsStatus(TtsStatus s) {
    if (_disposed) return;
    // Queue fully drained — commit any trailing chunk so the subtitle isn't
    // missing its last sentence.
    if (s == TtsStatus.idle && _currentChunkText.isNotEmpty) {
      _spokenChunks.add(_currentChunkText);
      _currentChunkText = '';
      _ref.read(liveAiTranscriptProvider.notifier).state =
          _spokenChunks.join(' ').trim();
    }
  }

  String _plain(Message m) {
    final buf = StringBuffer();
    for (final p in m.parts) {
      if (p is TextPart) buf.write(p.text);
    }
    return buf.toString();
  }

  String? _idFor(Message m) => m.openclawId ?? m.runId;
}

final voiceSessionProvider = Provider.family<VoiceSession, String>(
  (ref, sessionKey) {
    final session = VoiceSession(ref, sessionKey);
    ref.onDispose(session.dispose);
    return session;
  },
);
