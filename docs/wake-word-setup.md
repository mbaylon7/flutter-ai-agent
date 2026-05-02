# Wake word setup

Slice 1D enables an opt-in **"Hi OpenClaw" / "Hey OpenClaw"** wake word using
[Picovoice Porcupine](https://picovoice.ai/platform/porcupine/). Free for
personal / development use; **a paid commercial license is required before
distributing this app to end users**.

## One-time setup (developer)

1. Sign up at <https://console.picovoice.ai/> (free account).
2. From the console, train custom keywords:
   - **`Hi OpenClaw`** — for Android (and iOS if you ship there)
   - **`Hey OpenClaw`** — same
3. Download each platform's `.ppn` file. Drop them into:

   ```
   assets/wake-words/Hi-OpenClaw_en_android.ppn
   assets/wake-words/Hey-OpenClaw_en_android.ppn
   ```

   (Filenames are whatever the console gave you. The `WakeWordService`
   in `lib/data/voice/wake_word.dart` uses the literal paths above —
   adjust there if your console produced different names.)

4. Copy your **AccessKey** from the console.

## Running with the wake word enabled

The AccessKey is a secret; **do NOT commit it**. Pass via `--dart-define`:

```bash
flutter run --dart-define=PICOVOICE_KEY=<your-key>
```

Without `PICOVOICE_KEY` defined, `WakeWordService` is disabled silently
(toggle in Settings is still visible but inactive).

## Production licensing

Picovoice's free tier covers personal and development use. **Public app-store
distribution requires a paid Picovoice license** — contact Picovoice sales
before pushing a build to Google Play or the App Store.

If the license cost is unacceptable, the alternative is `openWakeWord`
(open-source ONNX keyword spotter) — but it has no first-class Flutter
plugin today, so it'd be a meaningful porting effort.
