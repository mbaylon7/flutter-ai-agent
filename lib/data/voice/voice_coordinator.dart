typedef AsyncCb = Future<void> Function();

class VoiceCoordinator {
  VoiceCoordinator({required this.stopTts, required this.stopStt});
  final AsyncCb stopTts;
  final AsyncCb stopStt;

  Future<void> startListening({required AsyncCb begin}) async {
    await stopTts(); // mutex: TTS off before STT on
    await begin();
  }

  Future<void> speak({required AsyncCb begin}) async {
    await stopStt(); // mutex: STT off before TTS on
    await begin();
  }
}
