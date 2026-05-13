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
          await _tts.setVoice({
            'name': preferred['name']!,
            'locale': preferred['locale']!,
          }).timeout(callBudget);
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
    // flutter_tts.setVoice only expects {name, locale}; strip our extras.
    await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
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
              final m = {'name': name, 'locale': locale};
              final g = _voiceGender(name);
              if (g != null) m['gender'] = g;
              // Carry quality hints when the platform exposes them — used by
              // _voiceScore to prefer high-quality network voices.
              final net = v['network_required']?.toString();
              if (net != null) m['network_required'] = net;
              final q = v['quality']?.toString();
              if (q != null) m['quality'] = q;
              all.add(m);
            }
          }
        }
      }
    }
    all.sort((a,b) => _voiceScore(b).compareTo(_voiceScore(a)));

    // Keep top 2 male + top 2 female (by score). Falls back to any remaining
    // voices to fill 4 slots if a gender is missing on this device.
    final males = all.where((v) => v['gender'] == 'male').take(2).toList();
    final females = all.where((v) => v['gender'] == 'female').take(2).toList();
    final picked = <Map<String,String>>[];
    for (var i = 0; i < 2; i++) {
      if (i < females.length) picked.add({...females[i], 'label': 'Female ${i + 1}'});
      if (i < males.length) picked.add({...males[i], 'label': 'Male ${i + 1}'});
    }
    if (picked.length < 4) {
      final remaining = all.where((v) => !picked.any((p) =>
          p['name'] == v['name'] && p['locale'] == v['locale']));
      for (final v in remaining) {
        if (picked.length >= 4) break;
        picked.add({...v, 'label': 'Voice ${picked.length + 1}'});
      }
    }
    return picked;
  }

  Map<String,String>? _pickPreferredVoice(List<Map<String,String>> voices) {
    if (voices.isEmpty) return null;
    final sorted = [...voices]..sort((a,b) => _voiceScore(b).compareTo(_voiceScore(a)));
    return sorted.first;
  }

  /// Best-effort gender inference from voice name. Returns 'male', 'female',
  /// or null when unknown. Heuristics: literal "male"/"female" first, then
  /// known Google TTS variant codes (Wavenet/Studio letters, Pixel `xxx`
  /// codes like `tpf`/`iom`).
  String? _voiceGender(String name) {
    final n = name.toLowerCase();
    if (n.contains('female')) return 'female';
    if (RegExp(r'(^|[^fe])male').hasMatch(n)) return 'male';

    // Google Wavenet/Studio/Neural/Journey: letter suffix encodes gender.
    final m = RegExp(r'(?:wavenet|neural2|studio|journey|news|polyglot)-([a-z])',
            caseSensitive: false)
        .firstMatch(n);
    if (m != null) {
      const female = {'a', 'c', 'e', 'f', 'g', 'h', 'o'};
      const male = {'b', 'd', 'i', 'j', 'n', 'q'};
      final letter = m.group(1)!.toLowerCase();
      if (female.contains(letter)) return 'female';
      if (male.contains(letter)) return 'male';
    }

    // Pixel/Android offline voices: 3-letter code, e.g. en-us-x-tpf-local.
    final p = RegExp(r'-x-([a-z]{3})-').firstMatch(n);
    if (p != null) {
      final code = p.group(1)!;
      const femaleCodes = {'tpf', 'tpc', 'iog', 'sfg'};
      const maleCodes = {'iol', 'iom', 'tpd', 'sfb'};
      if (femaleCodes.contains(code)) return 'female';
      if (maleCodes.contains(code)) return 'male';
      // Fallback: last letter often differentiates within a family.
      final last = code[2];
      if ('cfgh'.contains(last)) return 'female';
      if ('bdmn'.contains(last)) return 'male';
    }
    return null;
  }

  int _voiceScore(Map<String,String> v) {
    final n = (v['name'] ?? '').toLowerCase();
    var s = 0;
    if (n.contains('wavenet') || n.contains('neural') || n.contains('studio')
        || n.contains('premium') || n.contains('journey')) { s += 120; }
    if (n.contains('seanet') || n.contains('tpf')) { s += 70; }
    // Network voices on Android are the high-quality Google ones.
    if ((v['network_required'] ?? '').toLowerCase() == 'true') s += 40;
    final q = int.tryParse(v['quality'] ?? '');
    if (q != null) s += q;
    if (n.contains('default')) s -= 25;
    // Penalise locally-embedded "compact" voices — those are the robotic ones.
    if (n.contains('local') || n.contains('embedded') ||
        n.contains('compact')) {
      s -= 30;
    }
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
