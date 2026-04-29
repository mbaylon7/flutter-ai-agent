# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flutter POC for Speech-to-Text and Text-to-Speech on Android using Google's built-in services (no API keys, no cloud billing). Primary target is Android; iOS/macOS/Linux/Windows/web folders exist from `flutter create` but are not the focus.

## Commands

```bash
flutter pub get                       # install deps
flutter run                           # debug run on attached device
flutter analyze                       # lint (uses flutter_lints via analysis_options.yaml)
flutter test                          # run all tests
flutter test test/widget_test.dart    # run a single test file
flutter build apk --debug             # APK at build/app/outputs/flutter-apk/app-debug.apk
```

Dart SDK constraint: `^3.10.0`. Min Android SDK: API 21.

## Architecture

The entire app lives in a single file: `lib/main.dart`. There is no separation into widgets/services/models — `_SttTtsHomePageState` owns all STT, TTS, voice selection, animation, and UI logic. Before adding new features, decide whether to keep that single-file shape or extract; don't silently introduce a new layering.

Key behaviors that span multiple methods and are non-obvious from any one of them:

- **STT auto-restart loop.** `_onSpeechStatus` re-invokes `_startListening()` whenever the engine reports `done` while `_userWantsToListen` is still true and no final result has arrived. The two flags `_userWantsToListen` (user intent) and `_hasReceivedFinalResult` (engine output) together determine whether a `done` event ends the session or triggers a restart. Don't collapse them into `_isListening`.

- **STT/TTS mutual exclusion.** `_speakText` stops STT first and `_toggleListening` stops TTS first to avoid the speaker feeding back into the mic. Preserve this ordering when adding new entry points.

- **Voice selection pipeline.** `_initTts` → `_pickPreferredLanguage` → `_loadVoicesForLanguage` → `_pickPreferredVoice`, ranked by `_voiceScore` (WaveNet/Neural/Studio/Premium/Journey > SeaNet/TPF > default/local/embedded). The voice list is capped at `_maxVoices = 10` and stored as `{name, locale}` maps; `_voiceKey` is the composite identity used for selection because two voices can share a name.

- **Sound-level normalization.** `_minSoundLevel`/`_maxSoundLevel` are seeded with inverted sentinels (50000 / -50000) and learned from the live stream; `_normalizedSoundLevel` returns 0 until the range has been established. Don't replace with absolute thresholds — device mics vary.

- **Smart formatting.** `_smartFormat` runs on every partial STT result, not just finals, so the visible text capitalizes and spaces punctuation as the user speaks. It assumes `speech_to_text`'s `autoPunctuation: true` is doing the actual punctuation insertion.

- **Animation driver.** A single `AnimationController` (`_pulseController`, 1s reverse-repeat) drives both the mic ring and the wave-bar visualizer. In TTS mode the bars are synthesized from the pulse value + `Random`; in STT mode they're derived from `_normalizedSoundLevel`. `_animationActive = _userWantsToListen || _isSpeaking` gates both.

## Configuration constants

Tuned values live as fields on the State, not in a config file:
- `_speechRate = 0.56`, `_pitch = 1.10`
- `pauseFor: 3s`, `listenFor: 2 minutes` in `_startListening`
- `ListenMode.dictation`, `autoPunctuation: true`, `cancelOnError: false`

## Android specifics

`AndroidManifest.xml` declares `RECORD_AUDIO`, `INTERNET`, `BLUETOOTH`, `BLUETOOTH_CONNECT`. STT requires internet (Google's recognizer is online); TTS premium voices require internet on first use, basic voices work offline. The app explicitly sets the TTS engine to `com.google.android.tts` when available.
