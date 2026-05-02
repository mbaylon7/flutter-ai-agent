import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/state/voice_provider.dart';

void main() {
  test('starts idle', () {
    final m = VoiceStateMachine();
    expect(m.state, VoiceState.idle);
  });

  test('listening on user start; processing after final transcript', () {
    final m = VoiceStateMachine();
    m.userStart();
    expect(m.state, VoiceState.listening);
    m.gotFinalTranscript('hi');
    expect(m.state, VoiceState.processing);
  });

  test('responding when AI begins reply; idle when done', () {
    final m = VoiceStateMachine();
    m.userStart();
    m.gotFinalTranscript('x');
    m.aiBeganSpeaking();
    expect(m.state, VoiceState.responding);
    m.aiDoneSpeaking();
    expect(m.state, VoiceState.idle);
  });
}
