import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/voice/voice_coordinator.dart';

void main() {
  test('startListening cancels TTS first', () async {
    var ttsStops = 0; var listenStarts = 0;
    final c = VoiceCoordinator(
      stopTts: () async => ttsStops++,
      stopStt: () async {},
    );
    await c.startListening(begin: () async => listenStarts++);
    expect(ttsStops, 1);
    expect(listenStarts, 1);
  });

  test('speak cancels STT first', () async {
    var sttStops = 0; var speaks = 0;
    final c = VoiceCoordinator(
      stopTts: () async {},
      stopStt: () async => sttStops++,
    );
    await c.speak(begin: () async => speaks++);
    expect(sttStops, 1);
    expect(speaks, 1);
  });
}
