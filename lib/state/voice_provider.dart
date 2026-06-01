import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Voice-mode state machine. Drives the mic FAB, aurora, and subtitle UI.
///
/// Transitions are owned by [VoiceSession]; this notifier is the single
/// source of truth that widgets watch.
enum VoiceState {
  /// Session not running. Mic off, TTS off.
  idle,

  /// Continuous listening; mic open but no user speech detected yet.
  listening,

  /// STT is emitting partials with non-empty text — user is mid-utterance.
  userSpeaking,

  /// Final transcript captured; request in flight, awaiting assistant reply.
  processing,

  /// TTS is speaking at least one chunk of the assistant reply. STT muted.
  aiSpeaking,

  /// Explicitly paused by the user (long-press, or session retained but
  /// inactive). Mic off, TTS off.
  paused,

  /// Legacy alias retained for any existing widget code; equivalent to
  /// [aiSpeaking]. New code should use [aiSpeaking].
  responding,
}

class VoiceStateMachine extends StateNotifier<VoiceState> {
  VoiceStateMachine() : super(VoiceState.idle);

  void set(VoiceState next) => state = next;

  // --- legacy API kept for the old VoiceController one-shot path. ---
  void userStart() => state = VoiceState.listening;
  void userStop() => state = VoiceState.idle;
  void gotFinalTranscript(String _) => state = VoiceState.processing;
  void aiBeganSpeaking() => state = VoiceState.aiSpeaking;
  void aiDoneSpeaking() => state = VoiceState.idle;
  void interrupt() => state = VoiceState.idle;
}

final voiceStateProvider =
    StateNotifierProvider<VoiceStateMachine, VoiceState>(
  (_) => VoiceStateMachine(),
);

/// Live user-side caption: partial STT transcript while the user speaks.
/// Cleared on transition out of [VoiceState.userSpeaking] / [VoiceState.listening].
final liveUserTranscriptProvider = StateProvider<String>((_) => '');

/// Live AI-side caption: the assistant's streaming reply, updated as deltas
/// arrive. Cleared on transition back to [VoiceState.listening].
final liveAiTranscriptProvider = StateProvider<String>((_) => '');
