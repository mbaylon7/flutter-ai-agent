# Voice (STT/TTS) — Phased Plan v2

Status: **DRAFT — awaiting supervisor review**
Date: 2026-05-18

---

## Context

We want a live-conversation voice UX for this app (Gemini-Live style: open mic, speak naturally, AI responds, you can interrupt mid-sentence).

We will deliver this in **4 phases**, each independently testable and shippable. Phase 1 is a pure STT/TTS sandbox with **no AI, no openclaw, no pairing** — just to prove the voice tech works on real devices.

---

## Approaches evaluated

| Approach | Cost | Quality | Outcome |
|---|---|---|---|
| **Google native Android STT** (`speech_to_text` → Android `RecognitionService`) | Free | Excellent accuracy | ❌ System "beep" on every start/stop. No API to disable — intentional Google UX. Constant beeping in continuous mode. |
| **Vosk small** (40 MB on-device) | Free, offline | Mediocre | ❌ Accuracy too low. |
| **Vosk lgraph** (125 MB on-device) | Free, offline | Good accuracy | ❌ Test device CPU can't decode in real-time → buffer overflow. |
| **Deepgram cloud** | $200 free credit (~775 hrs), then $0.26/hr | Excellent | ⚠️ Best UX, but eventually paid. |
| **Sherpa-ONNX on device** | Free forever, offline | Good | ✅ Selected. |

---

# Phase 1 — STT/TTS Sandbox (no AI)

**Goal:** Prove Sherpa-ONNX works on real devices. Validate latency, accuracy, CPU, and that there are zero system beeps. **Keep the existing app UX** — only replace the voice tech behind it.

### UX (reuse current build)

The current shell stays intact:
- **Aurora animation + main voice screen** — unchanged
- **History drawer** — unchanged (each turn shows up as a "message" pair: what you said + what was spoken back)
- **Settings screen** — unchanged
- **Light / dark theme toggle** — unchanged
- **Mic button + visualiser** — unchanged
- **Voice ↔ chat mode toggle** — unchanged

**The only behavioural change in Phase 1:** the LLM / openclaw call is replaced with a local "echo" — whatever you said (voice mode) or typed (chat mode) is spoken back via TTS. So you can demo the full UX without any network, pairing, or AI cost.

**Both modes are testable:**
- **Voice mode** — exercises the full pipeline (mic → Sherpa STT → echo → TTS). Use this to verify STT accuracy, latency, no-beeps, and TTS playback.
- **Chat mode** — typed input → echo → TTS. Use this to verify TTS alone (no mic noise involved). Useful for isolating "is it the STT or the TTS that's wrong?" during testing.

### Subtitles

Two independent subtitle streams, both driven by Sherpa-ONNX:

| Stream | Source | Behaviour |
|---|---|---|
| **User subtitle** (while speaking) | Sherpa-ONNX STT partial results | Live transcript appears word-by-word as you speak |
| **AI subtitle** (while AI is replying) | Full echoed/LLM text up front + Sherpa-ONNX TTS sample-level timing to highlight the current word | Full message visible immediately; currently-spoken word highlighted; never freezes between sentences |

**Why subtitles change vs. today:** the current `flutter_tts` word-by-word reveal freezes between chunks (e.g. while the next sentence loads), which makes the user think the AI is done speaking when it isn't.

**Fix:** show the *full* message up front, and move a highlight cursor on the currently-spoken word. With Sherpa TTS we generate PCM ourselves, so we know exactly which audio sample corresponds to which word — word-precise highlighting becomes sample-accurate instead of relying on Android TTS progress callbacks. We can also pre-generate the next sentence while the current one plays, so playback is seamless (no inter-chunk pause).

### Scope

✅ In scope
- Mic capture (16 kHz mono PCM via `record`)
- Sherpa-ONNX streaming recognition
- Wire transcripts into the existing chat history / message bubbles
- TTS reads back the user's transcript (echo loop) using the existing chunker + subtitle sync
- All current UI: aurora, drawer, settings, theme, voice mode
- No-beep verification on test devices

❌ Out of scope (deferred to later phases)
- openclaw / gateway connection
- LLM / chat repository (real AI response)
- Pairing flow
- Barge-in (user interrupting mid-TTS)
- True streaming partials inside message bubbles (just final transcripts for now)

### Stack

| Layer | Tech | Size | Cost |
|---|---|---|---|
| Mic capture | `record` package, 16 kHz mono PCM, `AudioSource.VOICE_COMMUNICATION` | n/a | **Free** — open-source Flutter package |
| STT | `sherpa_onnx` package + `streaming-zipformer-en-2023-06-26` model | ~100 MB | **Free** — on-device, no cloud, no API key |
| TTS | `sherpa_onnx` package + `vits-piper-en_US-libritts_r-medium` model | ~80 MB | **Free** — on-device, no cloud, no API key |
| Audio playback | Native PCM playback (no Google TTS engine involved) | n/a | **Free** |

**Total ongoing cost: $0.** Everything runs on the device. No subscriptions, no API keys, no usage caps. No Google services in the voice path at all.

**APK impact:** +180 MB total (100 MB STT model + 80 MB TTS model). Phase 4 can move these to download-on-first-launch if size matters.

### Dart changes for Phase 1

- `lib/data/voice/stt_service.dart` — replace Vosk internals with Sherpa-ONNX STT + `record` mic capture (public API unchanged)
- `lib/data/voice/tts_service.dart` — replace `flutter_tts` with Sherpa-ONNX TTS + native PCM playback (public API unchanged; chunker + subtitle stream stay)
- `lib/state/voice_session.dart` — replace `chatRepository.send(...)` inside `_commitTurn` with a local echo: enqueue the user's transcript directly into TTS as if it were the AI's reply. Hide openclaw/pairing UI for this phase (settings flag).
- `pubspec.yaml` — add `sherpa_onnx` + `record`; remove `vosk_flutter` (+ its `dependency_override`) and `flutter_tts`; swap model assets
- `assets/models/` — drop Vosk zip; add Sherpa zipformer (STT) + Piper libritts_r (TTS) model files

### Acceptance criteria (Phase 1 done when…)

- [ ] Open the app → existing aurora UI loads, light/dark theme + settings + drawer behave exactly as today
- [ ] **Voice mode**: speak → user subtitle updates live (Sherpa partials); transcript lands in the history drawer; TTS echoes it back; AI subtitle shows the full echoed text with the current word highlighted
- [ ] **Chat mode**: type a message → it appears in the history drawer; TTS speaks it back; AI subtitle shows full text + word highlight
- [ ] Subtitle never freezes mid-message between TTS chunks
- [ ] Switching between voice ↔ chat mode mid-conversation doesn't break state
- [ ] **No system beeps** at any point during voice mode
- [ ] Tested on at least 2 devices (OnePlus CPH1989, Oppo A92)
- [ ] CPU usage stays under 60 % while listening (no buffer overflows)
- [ ] First-launch model load < 8 seconds

### Estimated effort: **~4 hours**

---

# Phase 2 — Wire STT to existing AI flow

**Goal:** Replace the current Vosk-based `SttService` with the validated Sherpa service. Voice mode in the main app now uses Sherpa, talks to the LLM through openclaw, and gets TTS replies — like today, but without beeps.

### Scope

- Swap `SttService` internals from Vosk → Sherpa (the Phase 1 implementation)
- Reuse existing `voice_session.dart` state machine
- Remove Vosk dependency + asset + permission_handler override
- Keep existing TTS chunker + word-by-word subtitle sync

### Acceptance criteria

- [ ] Voice mode in the main app works end-to-end (speak → AI → hear reply)
- [ ] No regressions in chat mode or pairing
- [ ] APK size measured and recorded

### Estimated effort: **~3 hours**

---

# Phase 3 — Barge-in / live conversation

**Goal:** Always-on mic with the ability to interrupt the AI mid-sentence. Gemini-Live UX.

### Scope

- Mic stays open during AI playback (rely on Android `VOICE_COMMUNICATION` echo cancellation)
- On real user speech detected during `aiSpeaking` → cancel TTS queue, transition to `userSpeaking`
- Tune endpoint detection: Sherpa endpoint signal + 1.5 s silence buffer
- Tune barge-in sensitivity threshold (energy gate to avoid AI bleed-through if AEC underperforms)

### Acceptance criteria

- [ ] Mid-sentence interruption cancels TTS and starts a new user turn within ~500 ms
- [ ] No phantom interrupts when AI is talking and user is silent
- [ ] Works on speaker (no headphones required)

### Estimated effort: **~3 hours**

---

# Phase 4 — Polish & fallback

**Goal:** Production-ready edges.

### Scope

- Better first-launch UX: model download with progress bar instead of bundling 100 MB in APK (optional)
- Error handling: mic permission denied, model file corrupt, Sherpa init failure
- Locale / language picker (if multi-language needed)
- Telemetry: log STT latency, error rate

### Estimated effort: **~4 hours**

---

## Total budget

| Phase | Effort | Cumulative |
|---|---|---|
| 1 — STT/TTS sandbox | 4 hrs | 4 hrs |
| 2 — Wire to AI | 3 hrs | 7 hrs |
| 3 — Barge-in | 3 hrs | 10 hrs |
| 4 — Polish | 4 hrs | 14 hrs |

~2 working days end-to-end.

---

## Risks / tradeoffs

1. **APK size grows to ~250 MB** (Sherpa model ~100 MB). Mitigation: Phase 4 can move model to runtime download.
2. **CPU load** untested on OnePlus CPH1989 with Sherpa zipformer. Phase 1 is specifically designed to surface this risk early — if it overflows like Vosk lgraph did, we fall back to the smaller Paraformer model or accept Deepgram free tier.
3. **English only** model. Multi-language requires a model swap.
4. **Accuracy ceiling** below Google native / Deepgram. If user feedback says quality is the bottleneck, escalate to Deepgram or self-hosted Whisper.

---

## Fallback path if Sherpa underperforms

1. Try smaller Paraformer model (~80 MB, lighter CPU)
2. Try Whisper.cpp tiny (~75 MB)
3. Switch to Deepgram free tier and revisit when credit runs out
4. Self-host Whisper on the existing Hetzner server (~1–2 days backend work, free forever after)

---

## Decision needed

- [ ] Approve Phase 1 scope and start implementation
- [ ] Adjust phasing / scope
- [ ] Pick a different STT path entirely
- [ ] Defer voice feature
