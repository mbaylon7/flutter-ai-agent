import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/data/voice/stt_service.dart';
import 'package:stt_tts/domain/markdown/strip_markdown.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/domain/voice/sentence_chunker.dart';
import 'package:stt_tts/state/repositories_provider.dart';
import 'package:stt_tts/state/ui_mode_provider.dart';
import 'package:stt_tts/state/voice_controller.dart';
import 'package:stt_tts/state/voice_provider.dart';

/// Orchestrates a continuous Gemini-Live-style conversation for one session.
///
/// State machine (owned by [voiceStateProvider]):
///
/// ```
///                 toggle()
///   idle ─────────────────────►  listening
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
///
/// Interruption: tap the mic during [aiSpeaking] → TTS queue cleared, state
/// returns to [listening]. Tap during any other state toggles pause/resume.
class VoiceSession {
  VoiceSession(this._ref, this.sessionKey);

  final Ref _ref;
  final String sessionKey;

  static const _chunker = SentenceChunker();

  // Listening / turn detection.
  StreamSubscription<SttTranscript>? _transcriptSub;
  Timer? _silenceTimer;
  static const _silenceTimeout = Duration(milliseconds: 1100);

  // AI streaming.
  StreamSubscription<List<Message>>? _messagesSub;
  bool _messagesReplayConsumed = false;
  final Set<String?> _knownAssistantIds = <String?>{};
  String? _activeAssistantKey;
  int _chunkCursor = 0;
  bool _ttsActive = false;

  bool _disposed = false;

  /// Resume / start the session. Idempotent.
  Future<void> start() async {
    if (_disposed) return;
    if (_ref.read(uiModeProvider) != UiMode.voice) return;

    final current = _ref.read(voiceStateProvider);
    if (current == VoiceState.listening ||
        current == VoiceState.userSpeaking ||
        current == VoiceState.processing ||
        current == VoiceState.aiSpeaking) {
      return;
    }

    _bindMessageStream();
    _bindTranscriptStream();

    _ref.read(voiceStateProvider.notifier).set(VoiceState.listening);
    final stt = _ref.read(sttServiceProvider);
    final coord = _ref.read(voiceCoordinatorProvider);
    await coord.startListening(begin: () => stt.startContinuous());
  }

  /// Tap-the-mic toggle. Behavior depends on current state:
  ///  - idle/paused           → start()
  ///  - listening             → pause()
  ///  - userSpeaking          → force end-of-turn (send what we have)
  ///  - processing            → no-op (request already in flight)
  ///  - aiSpeaking            → interrupt: stop TTS, return to listening
  Future<void> toggle() async {
    final current = _ref.read(voiceStateProvider);
    switch (current) {
      case VoiceState.idle:
      case VoiceState.paused:
        await start();
      case VoiceState.listening:
        await pause();
      case VoiceState.userSpeaking:
        await _forceEndOfTurn();
      case VoiceState.processing:
        // Request is in flight; ignore the tap.
        return;
      case VoiceState.aiSpeaking:
      case VoiceState.responding:
        await _interruptAi();
    }
  }

  /// Pause the session: mic off, TTS off, state retained.
  Future<void> pause() async {
    _silenceTimer?.cancel();
    final stt = _ref.read(sttServiceProvider);
    final tts = _ref.read(ttsServiceProvider);
    await stt.stop();
    await tts.clearQueue();
    _ttsActive = false;
    _ref.read(voiceStateProvider.notifier).set(VoiceState.paused);
    _ref.read(liveUserTranscriptProvider.notifier).state = '';
  }

  /// Fully end the session and release resources. Called when the user
  /// leaves voice mode.
  Future<void> stop() async {
    await pause();
    await _transcriptSub?.cancel();
    _transcriptSub = null;
    await _messagesSub?.cancel();
    _messagesSub = null;
    _messagesReplayConsumed = false;
    _ref.read(voiceStateProvider.notifier).set(VoiceState.idle);
    _ref.read(liveUserTranscriptProvider.notifier).state = '';
    _ref.read(liveAiTranscriptProvider.notifier).state = '';
  }

  void dispose() {
    _disposed = true;
    _silenceTimer?.cancel();
    _transcriptSub?.cancel();
    _messagesSub?.cancel();
  }

  // --- internal: STT pipeline -------------------------------------------

  void _bindTranscriptStream() {
    if (_transcriptSub != null) return;
    final stt = _ref.read(sttServiceProvider);
    _transcriptSub = stt.transcript.listen(_handleTranscript);
  }

  Future<void> _handleTranscript(SttTranscript t) async {
    if (_disposed) return;
    final mode = _ref.read(uiModeProvider);
    if (mode != UiMode.voice) return;

    final text = t.text.trim();
    if (text.isEmpty) return;

    final stateNotifier = _ref.read(voiceStateProvider.notifier);
    final current = _ref.read(voiceStateProvider);

    // Surface partials as live captions.
    _ref.read(liveUserTranscriptProvider.notifier).state = text;

    if (current == VoiceState.listening || current == VoiceState.aiSpeaking) {
      // User started talking — if AI is speaking, this would be barge-in,
      // but v1 ships without barge-in. Ignore unless we're in listening.
      if (current == VoiceState.listening) {
        stateNotifier.set(VoiceState.userSpeaking);
      }
    }

    // Restart the silence-since-last-partial timer.
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_silenceTimeout, () => _forceEndOfTurn());

    if (t.isFinal) {
      _silenceTimer?.cancel();
      await _commitTurn(text);
    }
  }

  Future<void> _forceEndOfTurn() async {
    if (_disposed) return;
    final current = _ref.read(voiceStateProvider);
    if (current != VoiceState.userSpeaking) return;
    final text = _ref.read(liveUserTranscriptProvider).trim();
    if (text.isEmpty) return;
    _silenceTimer?.cancel();
    await _commitTurn(text);
  }

  Future<void> _commitTurn(String text) async {
    if (_disposed) return;
    _ref.read(voiceStateProvider.notifier).set(VoiceState.processing);
    _ref.read(liveUserTranscriptProvider.notifier).state = '';
    _ref.read(liveAiTranscriptProvider.notifier).state = '';

    // Stop STT while we wait for / play back the reply.
    final stt = _ref.read(sttServiceProvider);
    await stt.stop();

    try {
      await _ref.read(chatRepositoryProvider).send(
            sessionKey: sessionKey,
            text: text,
          );
    } catch (_) {
      // Failed send: reopen the mic so the user can retry.
      _ref.read(voiceStateProvider.notifier).set(VoiceState.listening);
      await _ref.read(voiceCoordinatorProvider).startListening(
            begin: () => stt.startContinuous(),
          );
    }
  }

  // --- internal: assistant streaming + TTS chunker ---------------------

  void _bindMessageStream() {
    if (_messagesSub != null) return;
    final repo = _ref.read(chatRepositoryProvider);
    _messagesSub = repo.messages(sessionKey).listen(_handleMessages);
  }

  Future<void> _handleMessages(List<Message> list) async {
    if (_disposed) return;

    // First event is a replay of the current list — record all existing
    // assistant ids as "already handled" so we never re-speak them.
    if (!_messagesReplayConsumed) {
      _messagesReplayConsumed = true;
      for (final m in list) {
        if (m.role == Role.assistant) {
          _knownAssistantIds.add(_idFor(m));
        }
      }
      return;
    }

    if (_ref.read(uiModeProvider) != UiMode.voice) return;
    if (list.isEmpty) return;

    // Find the newest assistant message (last one in the list).
    Message? current;
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].role == Role.assistant) {
        current = list[i];
        break;
      }
    }
    if (current == null) return;

    final id = _idFor(current);

    // New assistant turn — reset cursor and start a fresh chunking pass.
    if (id != _activeAssistantKey) {
      _activeAssistantKey = id;
      _chunkCursor = 0;
      _knownAssistantIds.add(id);
      _ref.read(liveAiTranscriptProvider.notifier).state = '';
    }

    final plain = stripMarkdown(_plain(current));
    _ref.read(liveAiTranscriptProvider.notifier).state = plain;

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
  }

  Future<void> _finishAssistantTurn() async {
    final tts = _ref.read(ttsServiceProvider);
    await tts.awaitDrained();
    if (_disposed) return;
    _ttsActive = false;
    _activeAssistantKey = null;
    _chunkCursor = 0;

    // Return to listening if we're still in voice mode; otherwise stay
    // wherever the user navigated to.
    if (_ref.read(uiModeProvider) != UiMode.voice) return;
    final state = _ref.read(voiceStateProvider);
    if (state == VoiceState.idle || state == VoiceState.paused) return;

    _ref.read(voiceStateProvider.notifier).set(VoiceState.listening);
    _ref.read(liveAiTranscriptProvider.notifier).state = '';
    final stt = _ref.read(sttServiceProvider);
    await _ref.read(voiceCoordinatorProvider).startListening(
          begin: () => stt.startContinuous(),
        );
  }

  Future<void> _interruptAi() async {
    final tts = _ref.read(ttsServiceProvider);
    await tts.clearQueue();
    _ttsActive = false;
    _activeAssistantKey = null;
    _chunkCursor = 0;
    _ref.read(liveAiTranscriptProvider.notifier).state = '';
    _ref.read(voiceStateProvider.notifier).set(VoiceState.listening);
    final stt = _ref.read(sttServiceProvider);
    await _ref.read(voiceCoordinatorProvider).startListening(
          begin: () => stt.startContinuous(),
        );
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
