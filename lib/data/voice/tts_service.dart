import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:stt_tts/data/voice/voice_constants.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool _speaking = false;

  List<Map<String, String>> _voices = [];
  String? _selectedVoiceKey;

  final _statusCtl = StreamController<TtsStatus>.broadcast();
  final _progressCtl = StreamController<TtsProgress>.broadcast();

  Stream<TtsStatus> get status => _statusCtl.stream;
  /// Per-word boundary progress for karaoke highlight.
  Stream<TtsProgress> get progress => _progressCtl.stream;

  Future<void> init() async {
    _tts.setStartHandler(() {
      _speaking = true;
      _statusCtl.add(TtsStatus.speaking);
    });
    _tts.setCompletionHandler(() {
      _speaking = false;
      _statusCtl.add(TtsStatus.idle);
    });
    _tts.setCancelHandler(() {
      _speaking = false;
      _statusCtl.add(TtsStatus.idle);
    });
    _tts.setErrorHandler((m) {
      _speaking = false;
      _statusCtl.add(TtsStatus.failed);
    });
    _tts.setProgressHandler((text, start, end, word) {
      _progressCtl.add(TtsProgress(text: text, wordStart: start, wordEnd: end, word: word));
    });

    // Per-call budgets: a hung TTS engine (common on emulators with no voice
    // data) must not stall init forever. Each platform call gets a short
    // timeout; on TimeoutException we mark TTS unavailable and bail. speak()
    // already no-ops when !_ready, so the app remains usable for STT-only.
    const callBudget = Duration(seconds: 3);
    const queryBudget = Duration(seconds: 4);
    try {
      await _tts.awaitSpeakCompletion(false).timeout(callBudget);
      try {
        await _tts.setEngine('com.google.android.tts').timeout(callBudget);
      } catch (_) {/* fall back to system default engine */}
      await _tts.setVolume(1.0).timeout(callBudget);
      await _tts.setSpeechRate(VoiceConstants.speechRate).timeout(callBudget);
      await _tts.setPitch(VoiceConstants.pitch).timeout(callBudget);

      final lang = await _pickPreferredLanguage().timeout(
        queryBudget,
        onTimeout: () => 'en-US',
      );
      await _tts.setLanguage(lang).timeout(callBudget);
      _voices = await _loadVoicesForLanguage(lang).timeout(
        queryBudget,
        onTimeout: () => <Map<String, String>>[],
      );
      final preferred = _pickPreferredVoice(_voices);
      if (preferred != null) {
        try {
          await _tts.setVoice(preferred).timeout(callBudget);
        } catch (_) {/* keep going — voice selection is best-effort */}
        _selectedVoiceKey = _voiceKey(preferred);
      } else if (_voices.isNotEmpty) {
        _selectedVoiceKey = _voiceKey(_voices.first);
      }
      _ready = true;
    } on TimeoutException {
      _ready = false;
    } on MissingPluginException {
      _ready = false;
    } on PlatformException {
      _ready = false;
    }
  }

  bool get isReady => _ready;
  bool get isSpeaking => _speaking;
  List<Map<String, String>> get voices => List.unmodifiable(_voices);
  String? get selectedVoiceKey => _selectedVoiceKey;

  Future<void> speak(String text) async {
    if (!_ready) return;
    try {
      await _tts.stop();
      await Future.delayed(const Duration(milliseconds: 50));
      await _tts.speak(text);
    } on PlatformException catch (_) {
      _statusCtl.add(TtsStatus.failed);
    }
  }

  Future<void> stop() async => _tts.stop();

  Future<void> selectVoice(String key) async {
    final v = _voices.firstWhere((vv) => _voiceKey(vv) == key, orElse: () => {});
    if (v.isEmpty) return;
    await _tts.setVoice(v);
    _selectedVoiceKey = key;
  }

  // ===== picking logic — lifted from POC =====
  Future<String> _pickPreferredLanguage() async {
    try {
      final raw = await _tts.getLanguages;
      final langs = <String>[];
      if (raw is List) {
        for (final i in raw) {
          final s = i.toString();
          if (s.isNotEmpty) langs.add(s);
        }
      }
      const preferred = ['en-US','en_US','en-GB','en_GB'];
      for (final l in preferred) { if (langs.contains(l)) return l; }
      final en = langs.where((l) => l.toLowerCase().startsWith('en')).toList();
      if (en.isNotEmpty) return en.first;
      if (langs.isNotEmpty) return langs.first;
    } catch (_) {}
    return 'en-US';
  }

  Future<List<Map<String,String>>> _loadVoicesForLanguage(String lang) async {
    final raw = await _tts.getVoices;
    final n = lang.toLowerCase().replaceAll('_', '-');
    final prefix = n.split('-').first;
    final all = <Map<String,String>>[];
    if (raw is List) {
      for (final v in raw) {
        if (v is Map) {
          final name = v['name']?.toString();
          final locale = v['locale']?.toString();
          if (name != null && locale != null) {
            final nl = locale.toLowerCase().replaceAll('_','-');
            if (nl == n || nl.startsWith(prefix)) {
              all.add({'name': name, 'locale': locale});
            }
          }
        }
      }
    }
    all.sort((a,b) => _voiceScore(b).compareTo(_voiceScore(a)));
    final premium = all.where((v) => _voiceScore(v) > 0).toList();
    final result = premium.isNotEmpty ? premium : all;
    return result.length > VoiceConstants.maxVoices
        ? result.sublist(0, VoiceConstants.maxVoices) : result;
  }

  Map<String,String>? _pickPreferredVoice(List<Map<String,String>> voices) {
    if (voices.isEmpty) return null;
    final sorted = [...voices]..sort((a,b) => _voiceScore(b).compareTo(_voiceScore(a)));
    return sorted.first;
  }

  int _voiceScore(Map<String,String> v) {
    final n = (v['name'] ?? '').toLowerCase();
    var s = 0;
    if (n.contains('wavenet') || n.contains('neural') || n.contains('studio')
        || n.contains('premium') || n.contains('journey')) { s += 100; }
    if (n.contains('seanet') || n.contains('tpf')) { s += 60; }
    if (n.contains('female')) { s += 15; }
    if (n.contains('default')) { s -= 25; }
    if (n.contains('local') || n.contains('embedded')) { s -= 15; }
    return s;
  }

  String _voiceKey(Map<String,String> v) => '${v['name']}|${v['locale']}';

  Future<void> dispose() async {
    await _statusCtl.close();
    await _progressCtl.close();
  }
}

enum TtsStatus { idle, speaking, failed }

class TtsProgress {
  const TtsProgress({required this.text, required this.wordStart, required this.wordEnd, required this.word});
  final String text;
  final int wordStart;
  final int wordEnd;
  final String word;
}
