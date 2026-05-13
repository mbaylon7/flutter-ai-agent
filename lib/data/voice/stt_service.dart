import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:stt_tts/data/voice/voice_constants.dart';

class SttService {
  final SpeechToText _stt = SpeechToText();
  bool _enabled = false;
  bool _listening = false;
  bool _userWantsToListen = false;
  bool _hasReceivedFinalResult = false;

  /// When true, the engine restarts after every final result as well as
  /// after silence-driven `done` events, until [stop] is called. Used by
  /// voice mode for continuous-conversation listening.
  bool _continuous = false;
  Duration _pauseFor = VoiceConstants.pauseFor;
  String? _localeId;

  // Sound-level normalization (sentinel-seeded; see CLAUDE.md)
  double _minSoundLevel = VoiceConstants.soundLevelSeedMin;
  double _maxSoundLevel = VoiceConstants.soundLevelSeedMax;
  double _currentSoundLevel = 0;
  DateTime _lastLevelTick = DateTime.now();

  final _statusCtl = StreamController<SttStatus>.broadcast();
  final _transcriptCtl = StreamController<SttTranscript>.broadcast();
  final _levelCtl = StreamController<double>.broadcast();

  Stream<SttStatus> get status => _statusCtl.stream;
  Stream<SttTranscript> get transcript => _transcriptCtl.stream;
  Stream<double> get normalizedLevel => _levelCtl.stream;

  Future<void> init() async {
    try {
      _enabled = await _stt.initialize(
        onStatus: _onStatus, onError: _onError, debugLogging: false,
      );
      if (_enabled) {
        final locales = await _stt.locales();
        final sys = await _stt.systemLocale();
        _localeId = sys?.localeId;
        if (_localeId == null || !locales.any((l) => l.localeId == _localeId)) {
          final en = locales.where((e) => e.localeId.startsWith('en')).toList();
          _localeId = en.isNotEmpty ? en.first.localeId
              : (locales.isNotEmpty ? locales.first.localeId : null);
        }
      }
    } on PlatformException {
      _enabled = false;
    } on MissingPluginException {
      _enabled = false;
    }
  }

  bool get isAvailable => _enabled;
  bool get isListening => _listening;

  /// One-shot listen. Restarts on silence-only `done` events until a final
  /// result arrives or [stop] is called.
  Future<void> start({Duration? pauseFor}) async {
    if (!_enabled) return;
    _continuous = false;
    _pauseFor = pauseFor ?? VoiceConstants.pauseFor;
    _userWantsToListen = true;
    _hasReceivedFinalResult = false;
    _resetLevels();
    await _begin();
  }

  /// Continuous listen for voice-mode conversations. The engine restarts
  /// automatically after each final result, so partials and finals keep
  /// flowing until [stop] is called.
  Future<void> startContinuous({Duration? pauseFor}) async {
    if (!_enabled) return;
    _continuous = true;
    _pauseFor = pauseFor ?? VoiceConstants.pauseFor;
    _userWantsToListen = true;
    _hasReceivedFinalResult = false;
    _resetLevels();
    await _begin();
  }

  Future<void> stop() async {
    _userWantsToListen = false;
    _continuous = false;
    await _stt.stop();
    _listening = false;
    _statusCtl.add(SttStatus.idle);
  }

  Future<void> _begin() async {
    try {
      await _stt.listen(
        onResult: _onResult,
        onSoundLevelChange: _onLevel,
        localeId: _localeId,
        listenFor: VoiceConstants.listenFor,
        pauseFor: _pauseFor,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: VoiceConstants.listenMode,
          cancelOnError: false,
          autoPunctuation: VoiceConstants.autoPunctuation,
        ),
      );
    } on PlatformException {
      _userWantsToListen = false;
      _statusCtl.add(SttStatus.failed);
    }
  }

  void _onStatus(String s) {
    final nowListening = s == SpeechToText.listeningStatus;
    _listening = nowListening;
    _statusCtl.add(nowListening ? SttStatus.listening : SttStatus.idle);
    if (!nowListening && s == SpeechToText.doneStatus && _userWantsToListen) {
      // Continuous mode: always restart (engine cycles after each utterance).
      // One-shot mode: only restart if we haven't yet got a final result.
      if (!_continuous && _hasReceivedFinalResult) {
        _userWantsToListen = false;
        _hasReceivedFinalResult = false;
        return;
      }
      _hasReceivedFinalResult = false;
      Future.delayed(const Duration(milliseconds: 200), () {
        if (_userWantsToListen && !_listening) _begin();
      });
    }
  }

  void _onError(SpeechRecognitionError e) {
    final msg = e.errorMsg;
    if (msg.contains('error_no_match')) return; // transient
    _userWantsToListen = false;
    _statusCtl.add(SttStatus.failed);
  }

  void _onResult(SpeechRecognitionResult r) {
    if (r.recognizedWords.trim().isEmpty) return;
    final formatted = _smartFormat(r.recognizedWords);
    _transcriptCtl.add(SttTranscript(text: formatted, isFinal: r.finalResult));
    if (r.finalResult) _hasReceivedFinalResult = true;
  }

  void _onLevel(double l) {
    final now = DateTime.now();
    if (now.difference(_lastLevelTick).inMilliseconds < 100) return;
    _lastLevelTick = now;
    _minSoundLevel = min(_minSoundLevel, l);
    _maxSoundLevel = max(_maxSoundLevel, l);
    _currentSoundLevel = l;
    final range = (_maxSoundLevel - _minSoundLevel).abs();
    final norm = (range < 1e-6 || !_listening)
        ? 0.0
        : ((_currentSoundLevel - _minSoundLevel) / range).clamp(0.0, 1.0);
    _levelCtl.add(norm);
  }

  void _resetLevels() {
    _minSoundLevel = VoiceConstants.soundLevelSeedMin;
    _maxSoundLevel = VoiceConstants.soundLevelSeedMax;
    _currentSoundLevel = 0;
  }

  // Smart formatting (lifted from POC)
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
    await _statusCtl.close();
    await _transcriptCtl.close();
    await _levelCtl.close();
  }
}

enum SttStatus { idle, listening, failed }
class SttTranscript {
  const SttTranscript({required this.text, required this.isFinal});
  final String text;
  final bool isFinal;
}
