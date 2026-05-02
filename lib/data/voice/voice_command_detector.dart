import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;

enum VoiceCommand { stop, repeat, cancel }

class VoiceCommandDetector {
  final _stt = stt.SpeechToText();
  bool _running = false;
  StreamController<VoiceCommand>? _ctl;

  Future<void> start() async {
    if (_running) return;
    final ok = await _stt.initialize();
    if (!ok) return;
    _running = true;
    _ctl = StreamController<VoiceCommand>.broadcast();
    _listen();
  }

  Stream<VoiceCommand> get events => _ctl!.stream;

  Future<void> stop() async {
    _running = false;
    await _stt.stop();
    await _ctl?.close();
    _ctl = null;
  }

  void _listen() {
    if (!_running) return;
    _stt.listen(
      onResult: (r) {
        final t = r.recognizedWords.toLowerCase();
        if (RegExp(r'\b(stop)\b').hasMatch(t)) {
          _ctl?.add(VoiceCommand.stop);
        } else if (RegExp(r'\b(repeat)\b').hasMatch(t)) {
          _ctl?.add(VoiceCommand.repeat);
        } else if (RegExp(r'\b(cancel)\b').hasMatch(t)) {
          _ctl?.add(VoiceCommand.cancel);
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
