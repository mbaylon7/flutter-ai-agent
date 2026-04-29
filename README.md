# STT TTS POC

A Flutter proof-of-concept app demonstrating **Speech to Text (STT)** and **Text to Speech (TTS)** using Google's built-in Android services.

---

## Features

- **Speech to Text** — Tap the mic, speak, and see your speech transcribed into text in real time
- **Text to Speech** — Type or dictate text, then tap speak to hear it read aloud
- **Auto Punctuation** — Commas, periods, and question marks inserted automatically based on pauses and intonation
- **Smart Formatting** — Sentences are auto-capitalized and punctuation spacing is cleaned up
- **Pause Detection** — 3-second silence after speech automatically ends listening
- **Animated UI** — Pulsing mic ring, sound wave visualizer, and voice level indicator
- **TTS Animation** — Wave bars and ring animation respond while text is being spoken
- **Premium Voice Selection** — Automatically selects the best available voice (WaveNet, Neural, Studio)

---

## Tools & Libraries

| | **Speech to Text (STT)** | **Text to Speech (TTS)** |
|---|---|---|
| **Flutter Package** | [`speech_to_text`](https://pub.dev/packages/speech_to_text) v7.3.0 | [`flutter_tts`](https://pub.dev/packages/flutter_tts) v4.2.3 |
| **Engine** | Google Speech Recognition | Google Text-to-Speech |
| **Cost** | ✅ FREE | ✅ FREE |
| **Connectivity** | 🌐 Online (required) | 📴 Offline (basic voices) / 🌐 Online (premium voices) |
| **API Key** | Not needed | Not needed |
| **What it does** | Listens to human speech → converts to text | Reads text aloud → produces voice output |
| **Voice Quality** | — | Auto-selects best premium/neural voice |
| **Punctuation** | Auto-inserts commas, periods, question marks | — |
| **Limitation** | Needs internet for transcription | Premium voices need internet on first use |

> Both tools are free, use Google's built-in Android services, and require no API keys or subscriptions.

---

## Requirements

- Android 5.0+ (API 21+)
- Google Play Services installed on device
- Internet connection (required for STT, optional for TTS with basic voices)
- Microphone permission

---

## Tech Stack

| Component | Detail |
|---|---|
| Framework | Flutter (Dart) |
| Target Platform | Android |
| Min SDK | API 21 (Android 5.0) |
| Tested On | Android 14 (API 34), Android 16 (API 36) |
| Rendering | Impeller (OpenGLES) |

---

## Getting Started

### Run in debug mode

```bash
flutter pub get
flutter run
```

### Build APK

```bash
flutter build apk --debug
```

The APK will be at `build/app/outputs/flutter-apk/app-debug.apk`.

---

## Configuration

| Setting | Value |
|---|---|
| Speech Rate | 0.56 |
| Pitch | 1.10 |
| Pause Timeout | 3 seconds |
| Listen Duration | Up to 2 minutes |
| Auto Punctuation | Enabled |
| Dictation Mode | Enabled |

---

## App Permissions

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
```

---

## Total Cost

**$0** — No API keys, no subscriptions, no cloud billing required.
