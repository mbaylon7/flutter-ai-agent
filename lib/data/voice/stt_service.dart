import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

/// On-device streaming STT backed by Vosk (Kaldi). Replaces the Android
/// RecognitionService path so there are no system start/stop beeps and the
/// mic stays open continuously for live-conversation UX.
///
/// Public surface mirrors the original speech_to_text-based service so the
/// rest of the app doesn't need to change.
class SttService {
  static const _modelAsset = 'assets/models/vosk-model-en-us-0.22-lgraph.zip';
  static const _sampleRate = 16000;

  VoskFlutterPlugin? _vosk;
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;

  bool _enabled = false;
  bool _listening = false;

  StreamSubscription<String>? _partialSub;
  StreamSubscription<String>? _resultSub;

  // Vosk's SpeechService owns the mic and doesn't expose buffer-level
  // metrics, so the wave-bar visualiser is fed a synthesised pulse instead.
  Timer? _levelPulseTimer;
  final _rng = Random();

  final _statusCtl = StreamController<SttStatus>.broadcast();
  final _transcriptCtl = StreamController<SttTranscript>.broadcast();
  final _levelCtl = StreamController<double>.broadcast();

  Stream<SttStatus> get status => _statusCtl.stream;
  Stream<SttTranscript> get transcript => _transcriptCtl.stream;
  Stream<double> get normalizedLevel => _levelCtl.stream;

  Future<void> init() async {
    try {
      _vosk = VoskFlutterPlugin.instance();
      final modelPath = await ModelLoader().loadFromAssets(_modelAsset);
      _model = await _vosk!.createModel(modelPath);
      _recognizer = await _vosk!.createRecognizer(
        model: _model!,
        sampleRate: _sampleRate,
      );
      _speechService = await _vosk!.initSpeechService(_recognizer!);
      _enabled = true;
    } on PlatformException {
      _enabled = false;
    } on MissingPluginException {
      _enabled = false;
    } catch (_) {
      _enabled = false;
    }
  }

  bool get isAvailable => _enabled;
  bool get isListening => _listening;

  /// One-shot listen kept for API parity. Vosk treats every utterance as a
  /// final result already, so this is just an alias for [startContinuous].
  Future<void> start({Duration? pauseFor}) => startContinuous(pauseFor: pauseFor);

  Future<void> startContinuous({Duration? pauseFor}) async {
    if (!_enabled || _speechService == null) return;
    if (_listening) return;
    await _bindStreams();
    try {
      await _speechService!.start();
      _listening = true;
      _statusCtl.add(SttStatus.listening);
      _startLevelPulse();
    } on PlatformException {
      _statusCtl.add(SttStatus.failed);
    }
  }

  Future<void> stop() async {
    _stopLevelPulse();
    if (_speechService != null) {
      try {
        await _speechService!.stop();
      } catch (_) {/* best-effort */}
    }
    await _partialSub?.cancel();
    await _resultSub?.cancel();
    _partialSub = null;
    _resultSub = null;
    _listening = false;
    _statusCtl.add(SttStatus.idle);
  }

  Future<void> _bindStreams() async {
    await _partialSub?.cancel();
    await _resultSub?.cancel();
    _partialSub = _speechService!.onPartial().listen(_onPartial);
    _resultSub = _speechService!.onResult().listen(_onResult);
  }

  void _onPartial(String json) {
    final text = _extract(json, 'partial');
    if (text.isEmpty) return;
    _transcriptCtl.add(SttTranscript(
      text: _smartFormat(text),
      isFinal: false,
    ));
  }

  void _onResult(String json) {
    final text = _extract(json, 'text');
    if (text.isEmpty) return;
    _transcriptCtl.add(SttTranscript(
      text: _smartFormat(text),
      isFinal: true,
    ));
  }

  String _extract(String json, String key) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return (m[key] as String? ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  // ── Synthetic sound-level pulse ──────────────────────────────────────
  // Vosk's SpeechService owns the mic and doesn't expose buffer-level
  // metrics. We emit a gently varying pulse so the wave-bar visualiser
  // doesn't sit flat while the user is talking.
  void _startLevelPulse() {
    _stopLevelPulse();
    _levelPulseTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!_listening) return;
      final base = 0.25 + _rng.nextDouble() * 0.5;
      _levelCtl.add(base);
    });
  }

  void _stopLevelPulse() {
    _levelPulseTimer?.cancel();
    _levelPulseTimer = null;
    _levelCtl.add(0);
  }

  String _smartFormat(String text) {
    if (text.isEmpty) return text;
    var r = text;
    r = r[0].toUpperCase() + r.substring(1);
    r = r.replaceAllMapped(RegExp(r'([.!?])\s+(\w)'),
        (m) => '${m[1]} ${m[2]!.toUpperCase()}');
    r = r.replaceAllMapped(RegExp(r'([,;:])(\w)'),
        (m) => '${m[1]} ${m[2]}');
    r = r.replaceAll(RegExp(r'\s+([,.:;!?])'), r'$1');
    return r;
  }

  Future<void> dispose() async {
    await stop();
    await _statusCtl.close();
    await _transcriptCtl.close();
    await _levelCtl.close();
    _speechService?.dispose();
    _recognizer?.dispose();
    _model?.dispose();
  }
}

enum SttStatus { idle, listening, failed }

class SttTranscript {
  const SttTranscript({required this.text, required this.isFinal});
  final String text;
  final bool isFinal;
}
