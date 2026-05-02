import 'package:flutter_riverpod/flutter_riverpod.dart';

enum VoiceState { idle, listening, processing, responding }

class VoiceStateMachine extends StateNotifier<VoiceState> {
  VoiceStateMachine() : super(VoiceState.idle);

  void userStart() => state = VoiceState.listening;
  void userStop() => state = VoiceState.idle;
  void gotFinalTranscript(String _) => state = VoiceState.processing;
  void aiBeganSpeaking() => state = VoiceState.responding;
  void aiDoneSpeaking() => state = VoiceState.idle;
  void interrupt() => state = VoiceState.idle;
}

final voiceStateProvider =
    StateNotifierProvider<VoiceStateMachine, VoiceState>((_) => VoiceStateMachine());
