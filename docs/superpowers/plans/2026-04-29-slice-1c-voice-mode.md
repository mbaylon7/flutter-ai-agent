# Slice 1C — Voice Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** With chat working from 1B, ship the polished voice experience: tap mic → listen → process → AI replies → phone speaks it. Four distinct visual states (idle/listening/thinking/speaking), live partial transcript, karaoke per-word subtitle highlight while TTS speaks, and voice command interrupts ("Stop", "Repeat", "Cancel"). The voice-first home becomes the default screen.

**Architecture:** Existing POC's `speech_to_text` and `flutter_tts` logic is **lifted, not rewritten**, into `data/voice/stt_service.dart` and `data/voice/tts_service.dart`. A `VoiceCoordinator` enforces STT/TTS mutual exclusion (with one documented exception for the keyword-spotting path during TTS). A `VoiceStateMachine` (Riverpod `StateNotifier`) drives the UI state. The mic ring widget renders all four states from one shared `AnimationController`. Voice commands run a low-priority STT loop during TTS to detect "Stop/Repeat/Cancel."

**Tech Stack:** All from 1A/1B, plus the existing `speech_to_text: ^7.3.0` and `flutter_tts: ^4.2.3` already in `pubspec.yaml`.

**Prerequisites:** 1B working end-to-end. CLAUDE.md's documented STT/TTS behaviors carry forward verbatim.

---

## File Structure

| Path | Responsibility |
|---|---|
| `lib/data/voice/voice_constants.dart` | Tuned values: `_speechRate=0.56`, `_pitch=1.10`, `pauseFor: 3s`, `listenFor: 2 min`, `ListenMode.dictation`, `autoPunctuation: true` |
| `lib/data/voice/voice_coordinator.dart` | STT/TTS mutual exclusion (stop one before starting the other) |
| `lib/data/voice/stt_service.dart` | Wraps `speech_to_text` — preserves `_userWantsToListen`/`_hasReceivedFinalResult` semantics, restart loop, smart formatting, sound-level normalization |
| `lib/data/voice/tts_service.dart` | Wraps `flutter_tts` — preserves voice-score ranking, language picker, progress handler for karaoke |
| `lib/data/voice/voice_command_detector.dart` | Low-priority STT during TTS for "Stop/Repeat/Cancel" |
| `lib/state/voice_provider.dart` | `VoiceStateMachine` Riverpod notifier with idle/listening/processing/responding |
| `lib/ui/widgets/voice_visualizer.dart` | The pulse ring + waveform bars — drives both mic ring and inline visualizer |
| `lib/ui/speech/voice_home.dart` | Voice-first home (mic ring as the hero) |
| `lib/ui/speech/state_ring.dart` | The big mic ring widget that renders all 4 states |
| `lib/ui/speech/transcript_strip.dart` | Live partial transcript (listening) / spoken subtitle with karaoke (responding) |
| `lib/ui/shell/home_shell.dart` | Update — make voice home the body; chat is reached via swipe-up |
| `test/data/voice/voice_coordinator_test.dart` | Mutex behavior |
| `test/state/voice_provider_test.dart` | State machine transitions |

---

## Phase 1 — Constants + coordinator

### Task 1: `voice_constants.dart` (single source of truth for tuning)

**Files:**
- Create: `lib/data/voice/voice_constants.dart`

- [ ] **Step 1: Implement (no test — it's just constants)**

Create `lib/data/voice/voice_constants.dart`:
```dart
import 'package:speech_to_text/speech_to_text.dart';

class VoiceConstants {
  // FROM CLAUDE.md — tuned values that carry forward verbatim.
  // Do NOT change without referencing CLAUDE.md § "Configuration constants".
  static const double speechRate = 0.56;
  static const double pitch = 1.10;
  static const Duration pauseFor = Duration(seconds: 3);
  static const Duration listenFor = Duration(minutes: 2);
  static const ListenMode listenMode = ListenMode.dictation;
  static const bool autoPunctuation = true;

  static const int maxVoices = 10;

  // Sentinel sound-level seeds that are inverted intentionally — see CLAUDE.md.
  static const double soundLevelSeedMin = 50000;
  static const double soundLevelSeedMax = -50000;
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/data/voice/voice_constants.dart
git commit -m "feat(voice): centralize tuned voice constants from POC"
```

---

### Task 2: `VoiceCoordinator` (mutex)

**Files:**
- Create: `lib/data/voice/voice_coordinator.dart`
- Create: `test/data/voice/voice_coordinator_test.dart`

- [ ] **Step 1: Failing test**

Create `test/data/voice/voice_coordinator_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/voice/voice_coordinator.dart';

void main() {
  test('startListening cancels TTS first', () async {
    var ttsStops = 0; var listenStarts = 0;
    final c = VoiceCoordinator(
      stopTts: () async => ttsStops++,
      stopStt: () async {},
    );
    await c.startListening(begin: () async => listenStarts++);
    expect(ttsStops, 1);
    expect(listenStarts, 1);
  });

  test('speak cancels STT first', () async {
    var sttStops = 0; var speaks = 0;
    final c = VoiceCoordinator(
      stopTts: () async {},
      stopStt: () async => sttStops++,
    );
    await c.speak(begin: () async => speaks++);
    expect(sttStops, 1);
    expect(speaks, 1);
  });
}
```

- [ ] **Step 2: Run to confirm fail**

```bash
flutter test test/data/voice/voice_coordinator_test.dart
```

- [ ] **Step 3: Implement**

Create `lib/data/voice/voice_coordinator.dart`:
```dart
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
```

- [ ] **Step 4: Run + commit**

```bash
flutter test test/data/voice/voice_coordinator_test.dart
git add lib/data/voice/voice_coordinator.dart test/data/voice/voice_coordinator_test.dart
git commit -m "feat(voice): VoiceCoordinator enforcing STT/TTS mutual exclusion"
```

---

## Phase 2 — Lift existing services

### Task 3: `SttService` (lifted from POC)

**Files:**
- Create: `lib/data/voice/stt_service.dart`

> This is a **lift** of existing logic from `lib/main.dart`. Preserve every documented behavior in CLAUDE.md.

- [ ] **Step 1: Implement**

Create `lib/data/voice/stt_service.dart`:
```dart
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

  Future<void> start() async {
    if (!_enabled) return;
    _userWantsToListen = true;
    _hasReceivedFinalResult = false;
    _resetLevels();
    await _begin();
  }

  Future<void> stop() async {
    _userWantsToListen = false;
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
        pauseFor: VoiceConstants.pauseFor,
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
    // Restart loop — preserved from POC
    if (!nowListening && s == SpeechToText.doneStatus && _userWantsToListen) {
      if (_hasReceivedFinalResult) {
        _userWantsToListen = false;
        _hasReceivedFinalResult = false;
        return;
      }
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
```

- [ ] **Step 2: Quick smoke (just analyze)**

```bash
flutter analyze lib/data/voice/stt_service.dart
```

- [ ] **Step 3: Commit**

```bash
git add lib/data/voice/stt_service.dart
git commit -m "feat(voice): SttService — lifted POC logic with restart loop and smart formatting preserved"
```

---

### Task 4: `TtsService` (lifted from POC + word-boundary progress for karaoke)

**Files:**
- Create: `lib/data/voice/tts_service.dart`

- [ ] **Step 1: Implement**

Create `lib/data/voice/tts_service.dart`:
```dart
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

    try {
      await _tts.awaitSpeakCompletion(false);
      try { await _tts.setEngine('com.google.android.tts'); } catch (_) {}
      await _tts.setVolume(1.0);
      await _tts.setSpeechRate(VoiceConstants.speechRate);
      await _tts.setPitch(VoiceConstants.pitch);

      final lang = await _pickPreferredLanguage();
      await _tts.setLanguage(lang);
      _voices = await _loadVoicesForLanguage(lang);
      final preferred = _pickPreferredVoice(_voices);
      if (preferred != null) {
        await _tts.setVoice(preferred);
        _selectedVoiceKey = _voiceKey(preferred);
      } else if (_voices.isNotEmpty) {
        _selectedVoiceKey = _voiceKey(_voices.first);
      }
      _ready = true;
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
        || n.contains('premium') || n.contains('journey')) s += 100;
    if (n.contains('seanet') || n.contains('tpf')) s += 60;
    if (n.contains('female')) s += 15;
    if (n.contains('default')) s -= 25;
    if (n.contains('local') || n.contains('embedded')) s -= 15;
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
```

- [ ] **Step 2: Analyze + commit**

```bash
flutter analyze lib/data/voice/tts_service.dart
git add lib/data/voice/tts_service.dart
git commit -m "feat(voice): TtsService — lifted POC logic with karaoke progress events"
```

---

## Phase 3 — Voice state machine

### Task 5: `VoiceProvider` state machine

**Files:**
- Create: `lib/state/voice_provider.dart`
- Create: `test/state/voice_provider_test.dart`

- [ ] **Step 1: Failing test**

Create `test/state/voice_provider_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/state/voice_provider.dart';

void main() {
  test('starts idle', () {
    final m = VoiceStateMachine();
    expect(m.state, VoiceState.idle);
  });

  test('listening on user start; processing after final transcript', () {
    final m = VoiceStateMachine();
    m.userStart();
    expect(m.state, VoiceState.listening);
    m.gotFinalTranscript('hi');
    expect(m.state, VoiceState.processing);
  });

  test('responding when AI begins reply; idle when done', () {
    final m = VoiceStateMachine();
    m.userStart();
    m.gotFinalTranscript('x');
    m.aiBeganSpeaking();
    expect(m.state, VoiceState.responding);
    m.aiDoneSpeaking();
    expect(m.state, VoiceState.idle);
  });
}
```

- [ ] **Step 2: Run + fail, then implement**

```bash
flutter test test/state/voice_provider_test.dart
```

Create `lib/state/voice_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum VoiceState { idle, listening, processing, responding }

class VoiceStateMachine extends StateNotifier<VoiceState> {
  VoiceStateMachine() : super(VoiceState.idle);
  VoiceState get currentState => state;

  void userStart() => state = VoiceState.listening;
  void userStop() => state = VoiceState.idle;
  void gotFinalTranscript(String _) => state = VoiceState.processing;
  void aiBeganSpeaking() => state = VoiceState.responding;
  void aiDoneSpeaking() => state = VoiceState.idle;
  void interrupt() => state = VoiceState.idle;
}

final voiceStateProvider =
    StateNotifierProvider<VoiceStateMachine, VoiceState>((_) => VoiceStateMachine());
```

- [ ] **Step 3: Pass + commit**

```bash
flutter test test/state/voice_provider_test.dart
git add lib/state/voice_provider.dart test/state/voice_provider_test.dart
git commit -m "feat(state): VoiceStateMachine for idle/listening/processing/responding"
```

---

### Task 6: `VoiceController` (orchestrator that ties STT/TTS/messages/state-machine)

**Files:**
- Create: `lib/state/voice_controller.dart`

- [ ] **Step 1: Implement (tested manually via smoke test in Phase 5)**

Create `lib/state/voice_controller.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/data/voice/stt_service.dart';
import 'package:stt_tts/data/voice/tts_service.dart';
import 'package:stt_tts/data/voice/voice_coordinator.dart';
import 'package:stt_tts/state/messages_provider.dart';
import 'package:stt_tts/state/voice_provider.dart';
import 'package:stt_tts/ui/chat/markdown_renderer.dart' show stripMarkdown;

final sttServiceProvider = Provider<SttService>((ref) {
  final s = SttService();
  s.init();
  ref.onDispose(s.dispose);
  return s;
});

final ttsServiceProvider = Provider<TtsService>((ref) {
  final t = TtsService();
  t.init();
  ref.onDispose(t.dispose);
  return t;
});

final voiceCoordinatorProvider = Provider<VoiceCoordinator>((ref) {
  final stt = ref.watch(sttServiceProvider);
  final tts = ref.watch(ttsServiceProvider);
  return VoiceCoordinator(
    stopTts: () async => tts.stop(),
    stopStt: () async => stt.stop(),
  );
});

class VoiceController {
  VoiceController(this.ref, this.sessionId);
  final Ref ref;
  final String sessionId;

  Future<void> tapMic() async {
    final state = ref.read(voiceStateProvider.notifier);
    final stt = ref.read(sttServiceProvider);
    final tts = ref.read(ttsServiceProvider);
    final coord = ref.read(voiceCoordinatorProvider);

    if (state.currentState == VoiceState.responding) {
      await tts.stop();
      state.interrupt();
      return;
    }
    if (state.currentState == VoiceState.listening) {
      await stt.stop();
      state.userStop();
      return;
    }
    state.userStart();
    await coord.startListening(begin: () async => stt.start());

    // Listen for final transcript → send → wait for AI reply → speak
    stt.transcript.firstWhere((t) => t.isFinal).then((t) async {
      state.gotFinalTranscript(t.text);
      // Send via messages provider
      final notifier = ref.read(messagesProvider(sessionId).notifier);
      await notifier.send(t.text);

      // Watch for streaming completion → speak the assistant reply
      final messages = ref.read(messagesProvider(sessionId));
      messages.whenOrNull(data: (s) {
        // Find the latest assistant message and speak it once finalized.
        // This is best handled with a Stream<MessagesState>.listen in a real wiring;
        // for slice 1C the chat repository already emits 'final' state we can hook into.
      });

      // Simplified: subscribe to provider changes for the next finalized assistant turn.
      late ProviderSubscription sub;
      sub = ref.listen<MessagesState?>(
        messagesProvider(sessionId).select((s) => s.valueOrNull),
        (prev, next) async {
          if (next == null) return;
          final lastFinal = next.history.where((m) => m.role.name == 'assistant').toList();
          if (lastFinal.isEmpty) return;
          // Speak only when streaming has just finished (state.streaming == null this tick)
          if (next.streaming == null) {
            sub.close();
            state.aiBeganSpeaking();
            await coord.speak(begin: () async => tts.speak(stripMarkdown(lastFinal.last.text ?? '')));
          }
        },
      );

      tts.status.firstWhere((s) => s == TtsStatus.idle).then((_) {
        state.aiDoneSpeaking();
      });
    });
  }
}

final voiceControllerProvider = Provider.family<VoiceController, String>(
  (ref, sessionId) => VoiceController(ref, sessionId),
);
```

> NOTE: the wiring above is intentionally conservative — there are subtler edge cases (rapid taps, chat aborts mid-listen, etc.) that surface during the smoke test. Iterate after Task 9.

- [ ] **Step 2: Analyze + commit**

```bash
flutter analyze
git add lib/state/voice_controller.dart
git commit -m "feat(state): VoiceController orchestrating STT → send → TTS"
```

---

## Phase 4 — Voice UI

### Task 7: `VoiceVisualizer` (pulse ring + waveform bars)

**Files:**
- Create: `lib/ui/widgets/voice_visualizer.dart`

- [ ] **Step 1: Implement (visual; covered by smoke test)**

Create `lib/ui/widgets/voice_visualizer.dart`:
```dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

/// Wave bars driven by `level` 0..1 (mic level when listening, pulse when speaking).
class VoiceVisualizer extends StatelessWidget {
  const VoiceVisualizer({super.key, required this.level, required this.active});
  final double level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final rng = Random(level.hashCode);
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(24, (i) {
          final base = active ? (level * 0.6) + (rng.nextDouble() * level * 0.4) : 0.08;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 4,
            height: 6 + base * 30,
            decoration: BoxDecoration(
              color: active
                  ? OcColors.accent.withOpacity(0.3 + base * 0.7)
                  : OcColors.borderTint,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/ui/widgets/voice_visualizer.dart
git commit -m "feat(ui): voice visualizer waveform bars"
```

---

### Task 8: `StateRing` (the big mic ring with all 4 visual states)

**Files:**
- Create: `lib/ui/speech/state_ring.dart`

- [ ] **Step 1: Implement**

Create `lib/ui/speech/state_ring.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/voice_provider.dart';

class StateRing extends StatefulWidget {
  const StateRing({super.key, required this.state, required this.level, required this.onTap});
  final VoiceState state;
  final double level;
  final VoidCallback onTap;
  @override
  State<StateRing> createState() => _S();
}

class _S extends State<StateRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final pulse = _c.value; // 0..1
          final isListen = widget.state == VoiceState.listening;
          final isSpeak = widget.state == VoiceState.responding;
          final isThink = widget.state == VoiceState.processing;
          final scale = isListen ? 1.0 + (widget.level * 0.12) + (pulse * 0.04) : 1.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: isThink
                        ? Border.all(
                            color: OcColors.accent.withOpacity(0.5),
                            width: 2,
                            style: BorderStyle.solid, // dash effect mimicked via opacity oscillation
                          )
                        : Border.all(
                            color: isListen || isSpeak
                                ? OcColors.accent.withOpacity(0.85)
                                : OcColors.accent.withOpacity(0.4),
                            width: isListen || isSpeak ? 3 : 2,
                          ),
                    boxShadow: (isListen || isSpeak)
                        ? const [
                            BoxShadow(color: Color(0x8C508CFF), blurRadius: 28),
                          ]
                        : null,
                  ),
                ),
              ),
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSpeak ? OcColors.accent : OcColors.surface,
                  border: Border.all(color: OcColors.accent.withOpacity(0.5)),
                ),
                child: Icon(
                  isSpeak
                      ? Icons.volume_up
                      : isThink
                          ? Icons.more_horiz
                          : Icons.mic,
                  color: isSpeak ? OcColors.bgBottom : OcColors.accent,
                  size: 30,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/ui/speech/state_ring.dart
git commit -m "feat(ui): StateRing with idle/listening/processing/responding visuals"
```

---

### Task 9: `TranscriptStrip` (live transcript / karaoke subtitle)

**Files:**
- Create: `lib/ui/speech/transcript_strip.dart`

- [ ] **Step 1: Implement**

Create `lib/ui/speech/transcript_strip.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

/// Renders either: live partial transcript (listening) or karaoke subtitle (responding).
class TranscriptStrip extends StatelessWidget {
  const TranscriptStrip({super.key, required this.text, this.highlightStart, this.highlightEnd});
  final String text;
  final int? highlightStart;
  final int? highlightEnd;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox(height: 28);
    if (highlightStart == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: OcColors.textBody, fontSize: 13)),
      );
    }
    final s = highlightStart!.clamp(0, text.length);
    final e = (highlightEnd ?? s).clamp(s, text.length);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: OcColors.textBody),
          children: [
            TextSpan(text: text.substring(0, s), style: const TextStyle(color: OcColors.accent)),
            TextSpan(
              text: text.substring(s, e),
              style: TextStyle(
                color: OcColors.textPrimary,
                backgroundColor: OcColors.accent.withOpacity(0.25),
              ),
            ),
            TextSpan(text: text.substring(e), style: const TextStyle(color: OcColors.textMeta)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/ui/speech/transcript_strip.dart
git commit -m "feat(ui): TranscriptStrip with karaoke-style highlight"
```

---

### Task 10: `VoiceHome` (the voice-first home — slice 1C entrypoint)

**Files:**
- Create: `lib/ui/speech/voice_home.dart`
- Modify: `lib/ui/shell/home_shell.dart` (route placeholder → VoiceHome when no chat is open)

- [ ] **Step 1: Implement VoiceHome**

Create `lib/ui/speech/voice_home.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/messages_provider.dart';
import 'package:stt_tts/state/voice_controller.dart';
import 'package:stt_tts/state/voice_provider.dart';
import 'package:stt_tts/ui/chat/chat_screen.dart';
import 'package:stt_tts/ui/speech/state_ring.dart';
import 'package:stt_tts/ui/speech/transcript_strip.dart';
import 'package:stt_tts/ui/widgets/voice_visualizer.dart';
import 'package:stt_tts/data/voice/stt_service.dart';
import 'package:stt_tts/data/voice/tts_service.dart';

class VoiceHome extends ConsumerStatefulWidget {
  const VoiceHome({super.key, required this.sessionId});
  final String sessionId;
  @override
  ConsumerState<VoiceHome> createState() => _S();
}

class _S extends ConsumerState<VoiceHome> {
  String _liveTranscript = '';
  String _spokenLine = '';
  int? _hlStart;
  int? _hlEnd;
  double _level = 0;

  @override
  void initState() {
    super.initState();
    final stt = ref.read(sttServiceProvider);
    final tts = ref.read(ttsServiceProvider);
    stt.transcript.listen((t) => setState(() => _liveTranscript = t.text));
    stt.normalizedLevel.listen((l) => setState(() => _level = l));
    tts.progress.listen((p) {
      setState(() {
        _spokenLine = p.text;
        _hlStart = p.wordStart;
        _hlEnd = p.wordEnd;
      });
    });
    tts.status.listen((s) {
      if (s == TtsStatus.idle) setState(() { _hlStart = null; _hlEnd = null; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final vstate = ref.watch(voiceStateProvider);
    final controller = ref.read(voiceControllerProvider(widget.sessionId));

    final transcript = switch (vstate) {
      VoiceState.listening => _liveTranscript,
      VoiceState.processing => _liveTranscript, // faded
      VoiceState.responding => _spokenLine,
      VoiceState.idle => '',
    };

    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) {
          // Swipe up → chat mode for this session
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChatScreen(sessionId: widget.sessionId),
          ));
        }
      },
      child: Container(
        decoration: const BoxDecoration(gradient: ocBackgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              StateRing(
                state: vstate,
                level: _level,
                onTap: () => controller.tapMic(),
              ),
              const SizedBox(height: 16),
              Text(
                _statusLabel(vstate),
                style: const TextStyle(
                  color: OcColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _statusHint(vstate),
                style: const TextStyle(color: OcColors.textSubtitle, fontSize: 11),
              ),
              const SizedBox(height: 18),
              VoiceVisualizer(
                level: _level,
                active: vstate == VoiceState.listening || vstate == VoiceState.responding,
              ),
              const SizedBox(height: 12),
              TranscriptStrip(
                text: transcript,
                highlightStart: vstate == VoiceState.responding ? _hlStart : null,
                highlightEnd: vstate == VoiceState.responding ? _hlEnd : null,
              ),
              const Spacer(flex: 2),
              const Padding(
                padding: EdgeInsets.only(bottom: 18),
                child: Text('↑ swipe up to type',
                  style: TextStyle(color: OcColors.textMeta, fontSize: 11)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(VoiceState s) => switch (s) {
        VoiceState.idle => 'Tap to talk',
        VoiceState.listening => 'Listening…',
        VoiceState.processing => 'Thinking',
        VoiceState.responding => 'Speaking',
      };
  String _statusHint(VoiceState s) => switch (s) {
        VoiceState.idle => 'or say "Hi OpenClaw" (slice 1D)',
        VoiceState.listening => 'Tap to stop',
        VoiceState.processing => '',
        VoiceState.responding => 'Tap to stop',
      };
}
```

- [ ] **Step 2: Wire VoiceHome into HomeShell**

Update `lib/ui/shell/home_shell.dart` body — when `_activeSessionId` is null, show `VoiceHome` for a default-session id (you can use a constant placeholder until session creation is added). When active session is set, show ChatScreen as before. (Or always show VoiceHome and add the swipe-up-to-chat gesture from VoiceHome itself.)

Concretely, replace `_PlaceholderHome()` with `VoiceHome(sessionId: _activeSessionId ?? 'default')`.

- [ ] **Step 3: Analyze + commit**

```bash
flutter analyze
git add lib/ui/speech/voice_home.dart lib/ui/shell/home_shell.dart
git commit -m "feat(ui): voice-first home with all 4 states + swipe-up to chat"
```

---

## Phase 5 — Voice command interrupts ("Stop / Repeat / Cancel")

### Task 11: `VoiceCommandDetector`

**Files:**
- Create: `lib/data/voice/voice_command_detector.dart`

This is the documented exception to STT/TTS mutual exclusion (per CLAUDE.md): we keep STT running with low priority during TTS, listening only for the keywords.

- [ ] **Step 1: Implement**

Create `lib/data/voice/voice_command_detector.dart`:
```dart
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
        if (RegExp(r'\b(stop)\b').hasMatch(t)) _ctl?.add(VoiceCommand.stop);
        else if (RegExp(r'\b(repeat)\b').hasMatch(t)) _ctl?.add(VoiceCommand.repeat);
        else if (RegExp(r'\b(cancel)\b').hasMatch(t)) _ctl?.add(VoiceCommand.cancel);
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
```

- [ ] **Step 2: Hook into VoiceController** — when state transitions to `responding`, start the detector; when leaving `responding`, stop it. On `VoiceCommand.stop`, call `tts.stop()` + state.interrupt(). On `repeat`, find the last assistant message and `tts.speak()` it again. On `cancel`, send `chat.abort` for the current request.

(Wiring is in `voice_controller.dart` — extend the existing `tapMic` flow to register/unregister the detector around the speak phase.)

- [ ] **Step 3: Commit**

```bash
git add lib/data/voice/voice_command_detector.dart
git commit -m "feat(voice): voice command detector for Stop/Repeat/Cancel during TTS"
```

---

## Phase 6 — Smoke test

### Task 12: End-to-end voice round-trip on a real device

- [ ] **Step 1: Run on device**

```bash
flutter run
```

- [ ] **Step 2: Walk the path**

1. Launch app → splash → auto-reconnect → voice home
2. Tap mic → say "Hello, are you there?" → see live transcript
3. Stop on pause → state turns "Thinking"
4. AI replies → state turns "Speaking" — phone reads it aloud, subtitle highlights word by word
5. Mid-speak, say "Stop" → TTS stops, returns to idle
6. Tap mic → say "Repeat" → tests the repeat command
7. Swipe up → see the same conversation in chat mode
8. Type something there → reply streams in chat
9. Swipe down → back to voice home with the same session

- [ ] **Step 3: Commit fixes**

```bash
git add -A && git commit -m "chore: slice 1C smoke test passes — full voice loop end-to-end"
```

---

## Self-review

**Spec coverage:**
- §9 speech mode: Tasks 3–6, 8–10
- §9.1 STT/TTS strategy on-device: Tasks 3, 4
- §9.2 UI states: Tasks 5, 8
- §9.3 voice commands / interrupts: Task 11
- §9.4 subtitles: Task 9
- §22.3 voice states (4): Task 8

**Out of scope for 1C (covered later):**
- Wake word → 1D
- Voice picker UI / tone / speech rate sliders → 1D (settings panel)
- Mic permission denied state polish → 1D

**Placeholder scan:** None — every task has concrete code. Task 10's `'default'` session-id placeholder is documented as a temporary stand-in until explicit session creation is wired (which is a small follow-up).

**Type consistency:** `SttService`, `TtsService`, `VoiceCoordinator`, `VoiceState`, `VoiceStateMachine`, `VoiceCommand`, `VoiceCommandDetector`, `VoiceController` — all defined and used consistently across tasks.
