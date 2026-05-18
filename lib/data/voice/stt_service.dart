import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:stt_tts/data/voice/sherpa_assets.dart';

/// On-device streaming speech-to-text backed by Sherpa-ONNX (zipformer
/// transducer). Replaces the previous speech_to_text/Vosk implementations.
///
/// Public surface is identical to the prior service so [VoiceSession] and
/// other callers don't need to change:
///   - [init], [isAvailable], [isListening]
///   - [start] / [startContinuous] (alias) / [stop]
///   - [status], [transcript], [normalizedLevel] streams
///
/// Why Sherpa? It runs entirely in-process — no Android RecognitionService,
/// no system start/stop beeps. The model lives in `assets/models/` and is
/// copied to the app support directory on first launch.
class SttService {
  static const _modelDir = 'assets/models/sherpa-onnx-streaming-zipformer-en-kroko-2025-08-06';
  static const _sampleRate = 16000;
  static const _encoderFile = 'encoder.onnx';
  static const _decoderFile = 'decoder.onnx';
  static const _joinerFile = 'joiner.onnx';

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSub;

  bool _enabled = false;
  bool _listening = false;
  String _lastEmittedText = '';

  final _statusCtl = StreamController<SttStatus>.broadcast();
  final _transcriptCtl = StreamController<SttTranscript>.broadcast();
  final _levelCtl = StreamController<double>.broadcast();

  Stream<SttStatus> get status => _statusCtl.stream;
  Stream<SttTranscript> get transcript => _transcriptCtl.stream;
  Stream<double> get normalizedLevel => _levelCtl.stream;

  bool get isAvailable => _enabled;
  bool get isListening => _listening;

  Future<void> init() async {
    try {
      sherpa.initBindings();
      final encoder = await copyAssetFile('$_modelDir/$_encoderFile');
      final decoder = await copyAssetFile('$_modelDir/$_decoderFile');
      final joiner = await copyAssetFile('$_modelDir/$_joinerFile');
      final tokens = await copyAssetFile('$_modelDir/tokens.txt');

      final transducer = sherpa.OnlineTransducerModelConfig(
        encoder: encoder,
        decoder: decoder,
        joiner: joiner,
      );
      final model = sherpa.OnlineModelConfig(
        transducer: transducer,
        tokens: tokens,
        modelType: 'zipformer2',
        numThreads: 4,
        debug: false,
      );
      final config = sherpa.OnlineRecognizerConfig(
        model: model,
        ruleFsts: '',
        enableEndpoint: true,
        rule1MinTrailingSilence: 1.5,
        rule2MinTrailingSilence: 0.8,
        rule3MinUtteranceLength: 20,
        decodingMethod: 'modified_beam_search',
      );
      _recognizer = sherpa.OnlineRecognizer(config);
      _enabled = true;
    } on PlatformException catch (e, st) {
      // ignore: avoid_print
      print('[SttService.init] PlatformException: $e\n$st');
      _enabled = false;
    } on MissingPluginException catch (e, st) {
      // ignore: avoid_print
      print('[SttService.init] MissingPluginException: $e\n$st');
      _enabled = false;
    } catch (e, st) {
      // ignore: avoid_print
      print('[SttService.init] FAILED: $e\n$st');
      _enabled = false;
    }
  }

  /// One-shot listen — kept as an alias of [startContinuous] for API parity
  /// with the previous speech_to_text-based service.
  Future<void> start({Duration? pauseFor}) => startContinuous(pauseFor: pauseFor);

  Future<void> startContinuous({Duration? pauseFor}) async {
    if (!_enabled || _recognizer == null) return;
    if (_listening) return;

    if (!await _recorder.hasPermission()) {
      _statusCtl.add(SttStatus.failed);
      return;
    }

    _stream = _recognizer!.createStream();
    _lastEmittedText = '';

    try {
      final pcm = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        // VOICE_COMMUNICATION engages Android's built-in acoustic echo
        // cancellation — needed for Phase 3 barge-in, harmless in Phase 1.
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceCommunication,
        ),
      ));
      _audioSub = pcm.listen(_onPcm, onError: (_) {
        _statusCtl.add(SttStatus.failed);
      });
      _listening = true;
      _statusCtl.add(SttStatus.listening);
    } on PlatformException catch (e, st) {
      // ignore: avoid_print
      print('[SttService.startContinuous] PlatformException: $e\n$st');
      _statusCtl.add(SttStatus.failed);
      await _teardown();
    } catch (e, st) {
      // ignore: avoid_print
      print('[SttService.startContinuous] FAILED: $e\n$st');
      _statusCtl.add(SttStatus.failed);
      await _teardown();
    }
  }

  Future<void> stop() async {
    if (!_listening) return;
    await _teardown();
    _statusCtl.add(SttStatus.idle);
  }

  Future<void> _teardown() async {
    _listening = false;
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {/* best-effort */}
    _stream?.free();
    _stream = null;
  }

  void _onPcm(Uint8List bytes) {
    final stream = _stream;
    final rec = _recognizer;
    if (stream == null || rec == null) return;

    final samples = convertBytesToFloat32(bytes);
    _emitLevel(samples);

    stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
    while (rec.isReady(stream)) {
      rec.decode(stream);
    }

    final text = rec.getResult(stream).text.trim();
    final endpoint = rec.isEndpoint(stream);

    if (text.isNotEmpty && text != _lastEmittedText) {
      _lastEmittedText = text;
      _transcriptCtl.add(SttTranscript(
        text: _smartFormat(text),
        isFinal: false,
      ));
    }

    if (endpoint) {
      if (text.isNotEmpty) {
        // Zipformer never emits punctuation; append a period so each
        // utterance reads as a sentence and the AI subtitle/echo doesn't
        // run multiple sentences together.
        final withPeriod = text.endsWith('.') || text.endsWith('?') || text.endsWith('!')
            ? text
            : '$text.';
        _transcriptCtl.add(SttTranscript(
          text: _smartFormat(withPeriod),
          isFinal: true,
        ));
      }
      rec.reset(stream);
      _lastEmittedText = '';
    }
  }

  // Simple peak-amplitude → 0..1 envelope so the wave-bar visualiser has
  // something to react to. Avoids the noisy seeded-range approach by just
  // taking the max absolute sample in the chunk.
  void _emitLevel(Float32List samples) {
    if (samples.isEmpty) return;
    var peak = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i].abs();
      if (v > peak) peak = v;
    }
    // Compress so quiet speech still reads as motion in the UI.
    final norm = (peak * 3.0).clamp(0.0, 1.0);
    _levelCtl.add(norm);
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
    _recognizer?.free();
    _recognizer = null;
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
