import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;

enum VoiceCommand { stop, repeat, cancel }

class VoiceCommandDetector {
  final _stt = stt.SpeechToText();
  bool _running = false;
  // Always-available stream so callers can `listen` before/without start().
  // Closed only in dispose(); start()/stop() just toggle the listen loop.
  final _ctl = StreamController<VoiceCommand>.broadcast();

  Future<void> start() async {
    if (_running) return;
    final ok = await _stt.initialize();
    // If init fails (e.g. another STT session is already active on Android),
    // skip silently — the controller is still created so events.listen() is
    // safe; it just never emits.
    if (!ok) return;
    _running = true;
    _listen();
  }

  Stream<VoiceCommand> get events => _ctl.stream;

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _stt.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _ctl.close();
  }

  void _listen() {
    if (!_running) return;
    _stt.listen(
      onResult: (r) {
        final t = r.recognizedWords.toLowerCase();
        if (RegExp(r'\b(stop)\b').hasMatch(t)) {
          _ctl.add(VoiceCommand.stop);
        } else if (RegExp(r'\b(repeat)\b').hasMatch(t)) {
          _ctl.add(VoiceCommand.repeat);
        } else if (RegExp(r'\b(cancel)\b').hasMatch(t)) {
          _ctl.add(VoiceCommand.cancel);
        }
      },
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 30),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.search,
        cancelOnError: true,
      ),
    );
    Timer(const Duration(seconds: 30), _listen); // restart loop
  }
}
