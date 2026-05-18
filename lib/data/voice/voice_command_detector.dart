import 'dart:async';

/// Voice command keyword detector (stop/repeat/cancel).
///
/// In Phase 1 of the Sherpa-ONNX migration this is a no-op: the previous
/// implementation ran a second `speech_to_text` recognizer in parallel to
/// the main STT loop, which Sherpa can't easily do on the same mic stream.
/// The class is kept so existing callers compile; events stream simply
/// never emits. Phase 3 may revive this by adding a Sherpa-ONNX keyword-
/// spotting recognizer.
enum VoiceCommand { stop, repeat, cancel }

class VoiceCommandDetector {
  final _ctl = StreamController<VoiceCommand>.broadcast();
  bool _running = false;

  Stream<VoiceCommand> get events => _ctl.stream;

  Future<void> start() async {
    _running = true;
  }

  Future<void> stop() async {
    _running = false;
  }

  bool get isRunning => _running;

  Future<void> dispose() async {
    _running = false;
    await _ctl.close();
  }
}
