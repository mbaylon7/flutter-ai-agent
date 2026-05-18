import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:stt_tts/data/voice/sherpa_assets.dart';

/// On-device text-to-speech backed by Sherpa-ONNX (Piper VITS model).
/// Replaces the flutter_tts/Google-engine implementation — there is no
/// dependency on Google services and TTS runs fully offline.
///
/// Public API mirrors the previous service so [VoiceSession] and the
/// settings screen don't need to change. The voice-list-related APIs
/// ([voices], [selectVoice]) are kept for compatibility but only expose the
/// speaker IDs baked into the multi-speaker libritts_r model.
class TtsService {
  static const _modelDir = 'assets/models/vits-piper-en_US-libritts_r-medium';
  static const _modelFile = 'en_US-libritts_r-medium.onnx';

  sherpa.OfflineTts? _tts;
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<void>? _completeSub;

  bool _ready = false;
  bool _speaking = false;

  // Curated speaker picks from the libritts_r-medium 904-speaker model.
  // Gender labels are pulled from the LibriSpeech SPEAKERS.TXT manifest
  // (LibriTTS shares reader IDs with LibriSpeech). All six are from
  // train-clean-360 with ~25 min of speech each — the subset Piper was
  // fine-tuned on, so they're well-represented in the model.
  //
  // Key format is `libritts_r-<piperId>` so [selectVoice] can decode it
  // without an external lookup table.
  static const List<Map<String, String>> _curatedVoices = [
    {'key': 'libritts_r-9',   'name': 'Amanda',   'gender': 'Female', 'piperId': '9'},
    {'key': 'libritts_r-313', 'name': 'Nicole',   'gender': 'Female', 'piperId': '313'},
    {'key': 'libritts_r-731', 'name': 'Jeanette', 'gender': 'Female', 'piperId': '731'},
    {'key': 'libritts_r-16',  'name': 'Anthony',  'gender': 'Male',   'piperId': '16'},
    {'key': 'libritts_r-438', 'name': 'Todd',     'gender': 'Male',   'piperId': '438'},
    {'key': 'libritts_r-898', 'name': 'Eric',     'gender': 'Male',   'piperId': '898'},
  ];

  static const _defaultSpeakerId = 9; // Amanda (Female)
  int _speakerId = _defaultSpeakerId;
  final double _speed = 0.8;

  // Chunk queue for back-to-back synthesis. enqueueChunk() appends; _drain()
  // walks the queue and plays each utterance in turn.
  final Queue<String> _chunkQueue = Queue<String>();
  bool _draining = false;
  Completer<void>? _drainedCompleter;

  // Progress tracking for word-by-word subtitle. Each TTS utterance is
  // played as a single audio file; we use audioplayers' position events to
  // linearly interpolate which word is currently being spoken.
  String _currentText = '';
  List<String> _currentWords = const [];
  Duration _currentDuration = Duration.zero;

  final _statusCtl = StreamController<TtsStatus>.broadcast();
  final _progressCtl = StreamController<TtsProgress>.broadcast();

  Stream<TtsStatus> get status => _statusCtl.stream;
  Stream<TtsProgress> get progress => _progressCtl.stream;

  bool get isReady => _ready;
  bool get isSpeaking => _speaking;
  // The libritts_r model has multiple speakers; we expose them as a flat
  // list of {name, locale} entries for the existing voice-picker UI.
  List<Map<String, String>> get voices => _curatedVoices
      .map((v) => {
            'name': '${v['name']} (${v['gender']})',
            'locale': 'en-US',
            'key': v['key']!,
          })
      .toList(growable: false);
  String? get selectedVoiceKey => 'libritts_r-$_speakerId';

  Future<void> init() async {
    try {
      sherpa.initBindings();

      final modelPath = await copyAssetFile('$_modelDir/$_modelFile');
      final tokens = await copyAssetFile('$_modelDir/tokens.txt');
      final dataDir = await copyAssetDir('$_modelDir/espeak-ng-data');

      final vits = sherpa.OfflineTtsVitsModelConfig(
        model: modelPath,
        tokens: tokens,
        dataDir: dataDir,
      );
      final modelConfig = sherpa.OfflineTtsModelConfig(
        vits: vits,
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      );
      final ttsConfig = sherpa.OfflineTtsConfig(model: modelConfig);
      _tts = sherpa.OfflineTts(ttsConfig);

      _player = AudioPlayer();
      _positionSub = _player!.onPositionChanged.listen(_onPosition);
      _completeSub = _player!.onPlayerComplete.listen((_) => _onComplete());

      _ready = true;
    } on PlatformException catch (e, st) {
      // ignore: avoid_print
      print('[TtsService.init] PlatformException: $e\n$st');
      _ready = false;
    } on MissingPluginException catch (e, st) {
      // ignore: avoid_print
      print('[TtsService.init] MissingPluginException: $e\n$st');
      _ready = false;
    } catch (e, st) {
      // ignore: avoid_print
      print('[TtsService.init] FAILED: $e\n$st');
      _ready = false;
    }
  }

  Future<void> speak(String text) async {
    await clearQueue();
    await enqueueChunk(text);
    return awaitDrained();
  }

  Future<void> enqueueChunk(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    _chunkQueue.add(t);
    _drainedCompleter ??= Completer<void>();
    if (!_draining) {
      // ignore: discarded_futures — fire-and-forget; awaiting is via awaitDrained
      _drain();
    }
  }

  Future<void> awaitDrained() {
    if (!_draining && _chunkQueue.isEmpty) return Future.value();
    _drainedCompleter ??= Completer<void>();
    return _drainedCompleter!.future;
  }

  Future<void> clearQueue() async {
    _chunkQueue.clear();
    _draining = false;
    if (_player != null) {
      try {
        await _player!.stop();
      } catch (_) {/* best-effort */}
    }
    _speaking = false;
    _statusCtl.add(TtsStatus.idle);
    if (_drainedCompleter != null && !_drainedCompleter!.isCompleted) {
      _drainedCompleter!.complete();
    }
    _drainedCompleter = null;
  }

  Future<void> stop() => clearQueue();

  Future<void> _drain() async {
    if (_tts == null || _player == null) return;
    _draining = true;
    try {
      String? previousChunk;
      while (_chunkQueue.isNotEmpty) {
        final text = _chunkQueue.removeFirst();
        if (previousChunk != null) {
          // Pause length depends on the previous chunk's ending punctuation:
          // commas get a short breath, sentence terminators get a longer
          // beat. Falls back to a small generic gap for chunks without
          // trailing punctuation (e.g. force-split unpunctuated monologues).
          final lastCh = previousChunk[previousChunk.length - 1];
          final ms = lastCh == ',' ? 80 : 150;
          await Future<void>.delayed(Duration(milliseconds: ms));
        }
        previousChunk = text;
        await _synthesizeAndPlay(text);
      }
    } finally {
      _draining = false;
      _speaking = false;
      _statusCtl.add(TtsStatus.idle);
      if (_drainedCompleter != null && !_drainedCompleter!.isCompleted) {
        _drainedCompleter!.complete();
      }
      _drainedCompleter = null;
    }
  }

  Future<void> _synthesizeAndPlay(String text) async {
    final tts = _tts!;
    final player = _player!;

    final genConfig = sherpa.OfflineTtsGenerationConfig(
      sid: _speakerId,
      speed: _speed,
    );
    final audio = tts.generateWithConfig(text: text, config: genConfig);

    // Write the generated PCM to a temporary WAV file so audioplayers can
    // play it. In-memory PCM playback would be lower-latency but requires
    // an extra plugin; the WAV path is a Phase 1 shortcut.
    final tmp = await _writeWav(audio.samples, audio.sampleRate);

    _currentText = text;
    _currentWords = _splitWords(text);
    _currentDuration = Duration(
      milliseconds: ((audio.samples.length / audio.sampleRate) * 1000).round(),
    );
    _speaking = true;
    _statusCtl.add(TtsStatus.speaking);

    // Emit an initial progress event so the subtitle can render the full
    // text immediately with the cursor at word 0.
    _progressCtl.add(TtsProgress(
      text: text,
      wordStart: 0,
      wordEnd: _currentWords.isNotEmpty ? _currentWords.first.length : 0,
      word: _currentWords.isNotEmpty ? _currentWords.first : '',
    ));

    final completer = Completer<void>();
    _activeChunkCompleter = completer;
    await player.play(DeviceFileSource(tmp.path));
    await completer.future;
  }

  Completer<void>? _activeChunkCompleter;

  void _onPosition(Duration pos) {
    if (_currentWords.isEmpty || _currentDuration == Duration.zero) return;
    final fraction =
        (pos.inMilliseconds / _currentDuration.inMilliseconds).clamp(0.0, 1.0);
    final idx = (fraction * _currentWords.length).floor()
        .clamp(0, _currentWords.length - 1);

    // Word boundaries in [_currentText] (assuming single-space separation
    // after _splitWords cleaned it up).
    var start = 0;
    for (var i = 0; i < idx; i++) {
      start += _currentWords[i].length + 1;
    }
    final word = _currentWords[idx];
    _progressCtl.add(TtsProgress(
      text: _currentText,
      wordStart: start,
      wordEnd: start + word.length,
      word: word,
    ));
  }

  void _onComplete() {
    final c = _activeChunkCompleter;
    _activeChunkCompleter = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  Future<File> _writeWav(dynamic samples, int sampleRate) async {
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path,
        'sherpa-tts-${DateTime.now().millisecondsSinceEpoch}.wav');
    sherpa.writeWave(filename: path, samples: samples, sampleRate: sampleRate);
    return File(path);
  }

  List<String> _splitWords(String text) {
    return text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> selectVoice(String key) async {
    // Accept either the raw `libritts_r-<id>` key or a legacy
    // `<key>|<locale>` composite the existing picker still emits.
    final base = key.contains('|') ? key.split('|').first : key;
    final match = RegExp(r'^libritts_r-(\d+)$').firstMatch(base);
    final candidate =
        match != null ? int.tryParse(match.group(1)!) : null;
    if (candidate != null &&
        _curatedVoices.any((v) => v['piperId'] == candidate.toString())) {
      _speakerId = candidate;
    }
  }

  Future<void> dispose() async {
    await clearQueue();
    await _positionSub?.cancel();
    await _completeSub?.cancel();
    await _player?.dispose();
    _tts?.free();
    _tts = null;
    await _statusCtl.close();
    await _progressCtl.close();
  }
}

enum TtsStatus { idle, speaking, failed }

class TtsProgress {
  const TtsProgress({
    required this.text,
    required this.wordStart,
    required this.wordEnd,
    required this.word,
  });
  final String text;
  final int wordStart;
  final int wordEnd;
  final String word;
}
