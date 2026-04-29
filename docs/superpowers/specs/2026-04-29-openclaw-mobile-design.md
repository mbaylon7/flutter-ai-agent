---
project: OpenClaw Mobile
status: design — approved for planning
date: 2026-04-29
author: Marvin (with brainstorming assist)
---

# OpenClaw Mobile — Design

## 1. Goal & non-goals

**Goal.** A Flutter mobile app (Android first, iOS second) that is a full native client for **per-user AI agent gateways**, delivering both **Chat Mode** (text) and **Speech Mode** (voice) over a single shared conversation engine. Target audience is **non-technical end users** — each user gets their own agent instance, auto-provisioned by an external back-end service.

**Three supported agents (planned).** The app must talk to any of:
1. **OpenClaw** — verified protocol (this spec is built against it). **Slice 1 implements this one.**
2. **Nanobot** — back-end still being configured; protocol unknown today.
3. **Zeroclaw** — back-end still being configured; protocol unknown today.

The app uses a **pluggable gateway interface** so adding Nanobot and Zeroclaw later is dropping in two new implementations of the same Dart interface, not rewriting the chat / voice / sessions code.

**Non-goals.**
- Re-implementing what each gateway already provides: AI orchestration, history-of-record, memory, plugins, command catalog, model selection, dreaming, search.
- Hosting our own back-end. The original spec's Vue/Quasar + Laravel layer is dropped. **The provisioning service (auth, container lifecycle, billing, agent dispatch) is a separate back-end project owned outside this Flutter codebase.**
- Browser/desktop targets.

**Audience constraint (drives every UX decision).** The user never sees a gateway URL, a token, a device ID, an IP address, the word "container," or any technical jargon. Hosted users just sign up and use the app. Power users (post-trial) can choose **BYO** (Bring Your Own) and pick which agent to connect to.

## 2. System boundary

```
┌──────────────────┐      WebSocket          ┌────────────────────┐
│ OpenClaw Mobile  │  ws(s)://<host>:<port>/ │ Agent gateway      │
│ (Flutter)        │ ◄══════════════════════►│ (slice 1 = OpenClaw│
│                  │  RPC: req / res / event │   running locally) │
└──────────────────┘  ECDSA-signed connect   └────────────────────┘
        │ on-device:
        ▼
  · Mic capture
  · STT (speech_to_text)
  · TTS (flutter_tts)
  · Wake word (Picovoice — slice 1, off by default)
  · Secure key/token storage
  · Minimal local cache
```

The **gateway is the source of truth** for everything except local UI state, device identity, and wake-word listening. This is the most important constraint in the design.

## 3. Architecture choice — thin client over local-first

| Option | Pro | Con |
|---|---|---|
| **Thin client (chosen)** | Simplest, no desync, smallest code surface | Cold start needs WS handshake before sessions render |
| Local-first w/ full mirror | Instant cold start, true offline reads | Sync code is the #1 bug source in apps like this |
| Hybrid (current + recent N) | Middle ground | Cache eviction is its own bug surface |

**Decision: thin client.** The gateway is on a LAN reachable in milliseconds. Personal-volume chat doesn't justify a sync layer. We retain the option to upgrade later because all gateway access is funneled through one repository layer (§5).

## 4. Component / folder layout

The current `lib/main.dart` (~880 LOC, single `StatefulWidget`) is restructured into the layout below. Working STT/TTS logic is **lifted, not rewritten**, with all the non-obvious behaviors documented in `CLAUDE.md` preserved.

The `data/gateway/` folder defines a single **agent-agnostic interface** (`GatewayClient`) plus per-agent implementations under `data/gateway/agents/`. Slice 1 ships only the OpenClaw implementation. Nanobot and Zeroclaw drop in later as sibling files; nothing in `domain/`, `state/`, or `ui/` changes when they land.

```
lib/
├── main.dart                         # bootstrap + DI container (Riverpod ProviderScope)
├── app.dart                          # MaterialApp, routing, theme
├── core/
│   ├── env.dart                      # secure storage adapter
│   ├── result.dart                   # Result<T,E>
│   ├── ids.dart                      # request id / instance id / device id helpers
│   └── logger.dart
├── data/
│   ├── gateway/
│   │   ├── gateway_client.dart       # ABSTRACT interface — agent-agnostic public surface
│   │   ├── gateway_factory.dart      # picks impl from agent type + connection info
│   │   ├── shared/
│   │   │   ├── ws_connection.dart    # raw WS lifecycle, reconnect, ping (reusable)
│   │   │   ├── device_identity.dart  # ECDSA P-256 keypair gen + persistent storage
│   │   │   └── envelope_codec.dart   # JSON helpers reused across agents
│   │   └── agents/
│   │       ├── openclaw/             # SLICE 1: full impl
│   │       │   ├── openclaw_client.dart       # implements GatewayClient
│   │       │   ├── connect_params.dart        # OpenClaw-specific connect params
│   │       │   ├── device_proof.dart          # OpenClaw's canonical `nt` signing
│   │       │   ├── auth.dart                  # token / deviceToken selection
│   │       │   ├── methods.dart               # typed wrappers for OpenClaw RPC methods
│   │       │   └── events.dart                # OpenClaw event models
│   │       ├── nanobot/              # placeholder; filled when protocol arrives
│   │       └── zeroclaw/             # placeholder; filled when protocol arrives
│   ├── voice/
│   │   ├── stt_service.dart          # wraps speech_to_text (current logic preserved)
│   │   ├── tts_service.dart          # wraps flutter_tts (current logic preserved)
│   │   ├── voice_coordinator.dart    # STT/TTS mutual exclusion + voice state machine
│   │   ├── voice_constants.dart      # tuned values (rate 0.56, pitch 1.10, pauseFor 3s, …)
│   │   └── wake_word.dart            # Picovoice Porcupine wrapper (slice 1, off by default)
│   ├── secure/
│   │   └── secure_store.dart         # flutter_secure_storage adapter (Keystore/Keychain)
│   └── cache/
│       └── local_store.dart          # sqflite: sessions list + last-seen tail
├── domain/
│   ├── models/                       # Session, Message, Command, Voice, Tone, Skill
│   └── repositories/
│       ├── chat_repository.dart      # uses gateway_client + cache
│       ├── session_repository.dart
│       ├── command_repository.dart   # tools.catalog + skills.* + commands list
│       └── settings_repository.dart
├── state/                            # Riverpod providers
│   ├── connection_provider.dart      # connecting / authed / disconnected
│   ├── sessions_provider.dart        # paginated list, subscribed to live updates
│   ├── messages_provider.dart        # by sessionId
│   ├── voice_provider.dart           # idle / listening / processing / responding
│   ├── mode_provider.dart            # speech vs chat
│   └── settings_provider.dart
└── ui/
    ├── shell/                        # scaffold, gesture handlers, status banner
    ├── onboarding/                   # manual pair form (URL + token, slice 1)
    ├── chat/                         # message list, composer (with mini mic), bubbles, deltas, sources sheet
    ├── speech/                       # mic ring, waveform, subtitles, state machine
    ├── sessions/                     # list, search, filter chips, pin/rename/delete
    ├── settings/                     # voice/tone, wake word toggle, pair info, privacy/about
    └── widgets/                      # waveform, pulse ring, loading, etc.
```

**State management: Riverpod 2.x** — stream-friendly (we have many WS streams), test-friendly, no `BuildContext` coupling.

## 4.1 The `GatewayClient` interface

All three agents must satisfy this contract. UI / state / domain code only ever sees this interface — never an agent-specific class.

```dart
abstract class GatewayClient {
  /// Cold connect: open socket, authenticate, return when ready.
  Future<void> connect({required ConnectionConfig config});
  Future<void> disconnect();

  /// Connection state for the UI banner.
  Stream<ConnectionState> connectionState;

  /// Sessions
  Future<List<Session>> listSessions();
  Stream<SessionListEvent> watchSessions();           // adds / updates / deletes
  Future<void> renameSession(String id, String title);
  Future<void> deleteSession(String id);

  /// Chat
  Future<List<Message>> loadHistory(String sessionId, {String? cursor});
  Future<void> sendMessage(String sessionId, String text, {required String requestId});
  Stream<ChatStreamEvent> watchChat(String sessionId);// deltas / finals / sources / fails
  Future<void> abort(String requestId);

  /// Capabilities — UI uses this to hide features the current agent doesn't support
  GatewayCapabilities get capabilities;               // {streaming, sources, plugins, …}
}
```

The interface is **as wide as needed for slice 1 features**; it grows only when a later slice adds a feature to the UI. Each agent declares its capabilities so the UI can hide tool-call / sources / plugin chrome on agents that don't have them.

## 5. OpenClaw wire protocol (slice 1 reference impl)

### 5.1 Frame envelope

Every frame is JSON, discriminated by `type`:

```json
// client → server: request
{"type":"req","id":"<uuid>","method":"<dotted.name>","params":{...}}

// server → client: response (correlated by id)
{"type":"res","id":"<uuid>","ok":true,"result":{...}}
{"type":"res","id":"<uuid>","ok":false,"error":{"code":"<CODE>","message":"...","details":{...}}}

// server → client: server-pushed event
{"type":"event","event":"<dotted.name>","payload":{...},"seq":<int>}
```

The `seq` on events is monotonic; the client tracks `lastSeq` and reports gaps via an `onGap` callback. We surface gaps to telemetry, not the user.

### 5.2 Connect (auth) flow

1. Client opens `ws(s)://<host>:18789/`.
2. Server immediately pushes `connect.challenge`:
   ```json
   {"type":"event","event":"connect.challenge","payload":{"nonce":"<uuid>","ts":<ms>}}
   ```
3. Client sends RPC `connect`:
   ```json
   {
     "type": "req",
     "id": "<uuid>",
     "method": "connect",
     "params": {
       "minProtocol": 3,
       "maxProtocol": 3,
       "client": {
         "id": "openclaw-android",       // or "openclaw-ios" / "openclaw-macos"
         "version": "<app version>",
         "platform": "android",
         "mode": "webchat",
         "instanceId": "<persistent uuid>"
       },
       "role": "operator",
       "scopes": [
         "operator.admin", "operator.read", "operator.write",
         "operator.approvals", "operator.pairing"
       ],
       "device": {
         "id": "<deviceId>",
         "publicKey": "<base64 P-256 SPKI>",
         "signature": "<base64 ECDSA signature>",
         "signedAt": <ms>,
         "nonce": "<challenge nonce>"
       },
       "caps": ["tool-events"],
       "auth": {
         "token": "<gateway token | omit if using deviceToken>",
         "deviceToken": "<persisted device token | omit on first connect>",
         "password": "<optional>"
       },
       "userAgent": "OpenClaw-Mobile/<version> Android/<api>",
       "locale": "<bcp47>"
     }
   }
   ```
4. Server returns Hello in the matching `res`. On success, payload includes `auth:{role, scopes, deviceToken}`. **Client persists `deviceToken`** to secure storage and uses it for future connects (so the shared gateway token is needed only at first pair).
5. Failure modes: server returns `INVALID_REQUEST`, `AUTH_TOKEN_MISMATCH`, or `AUTH_DEVICE_TOKEN_MISMATCH`. Some errors carry `recommendedNextStep: "retry_with_device_token"` — client auto-retries once.

### 5.3 Device proof

Device identity is generated **once per install**, stored in `flutter_secure_storage` (Keystore/Keychain backed):

- Keypair: ECDSA P-256
- `deviceId`: random UUID (also persisted)
- On every connect, sign a canonical concatenation of `{deviceId, clientId, clientMode, role, scopes, signedAtMs, token (or null), nonce}` per the gateway's `nt` canonical-string function (exact byte-for-byte format **must be replayed and matched** before first commit of the connection layer — this is the first task in the impl plan).
- Public key sent in SPKI/base64 form.

### 5.4 RPC method catalog (62 methods)

Grouped:

| Domain | Methods |
|---|---|
| **Connection** | `connect`, `health`, `status`, `system-presence`, `last-heartbeat` |
| **Sessions** | `sessions.list`, `sessions.delete`, `sessions.patch`, `sessions.reset`, `sessions.steer`, `sessions.subscribe`, `sessions.compact`, `sessions.compaction.list`, `sessions.usage`, `sessions.usage.logs`, `sessions.usage.timeseries` |
| **Chat** | `chat.send`, `chat.abort`, `chat.history` |
| **Agents** | `agent.identity.get`, `agents.list`, `agents.files.get`, `agents.files.list`, `agents.files.set` |
| **Channels** | `channels.status`, `channels.logout` |
| **Config** | `config.get`, `config.patch`, `config.openFile`, `config.schema`, `config.schema.lookup` |
| **Cron** | `cron.add`, `cron.list`, `cron.remove`, `cron.run`, `cron.runs`, `cron.status`, `cron.update` |
| **Devices** | `device.pair.approve`, `device.pair.list`, `device.pair.reject`, `device.token.rotate`, `device.token.revoke` |
| **Memory / Doctor** | `doctor.memory.dreamDiary`, `doctor.memory.status` |
| **Exec policy** | `exec.approvals.get`, `exec.approvals.set`, `exec.approvals.node.get`, `exec.approvals.node.set` |
| **Logs** | `logs.tail` |
| **Models** | `models.list` |
| **Nodes** | `node.list` |
| **Skills (plugins)** | `skills.detail`, `skills.install`, `skills.search`, `skills.status`, `skills.update` |
| **Tools** | `tools.catalog`, `tools.effective` |
| **Update** | `update.run` |
| **Usage** | `usage.cost` |
| **Web login** | `web.login.start`, `web.login.wait` |
| **Wiki** | `wiki.get`, `wiki.importInsights`, `wiki.palace` |

The Flutter app uses a **subset** in slice 1 (`connect`, `sessions.list`, `sessions.subscribe`, `sessions.patch`, `sessions.delete`, `chat.send`, `chat.abort`, `chat.history`, `models.list`, `health`); the rest are wrapped lazily as features need them.

### 5.5 Server-pushed events (known)

- **Auth:** `connect.challenge`, `auth.required`, `auth.failed`, `auth.deviceToken`, `auth.role`, `auth.scopes`
- **Chat:** `chat.disconnected`, `chat.history`, `chat.refreshTitle`, `chat.thinkingToggle`, `chat.toolCallsToggle`, `chat.hideCronSessions`, `chat.showCronSessions`, `chat.showCronSessionsHidden`, `chat.focusToggle`, `chat.onboardingDisabled`, `chat.side`
- **Stream:** `stream.trim`
- **Command:** `command.executeLocal`
- **Gateway:** `gateway.controlUi`

The exact streaming-token event name (e.g. `chat.message`, `chat.delta`) is not yet captured from a real exchange — **resolved as task 1 of the implementation plan**, before any stream-rendering code is written.

### 5.6 Reconnect / heartbeat

- Reconnect with exponential backoff: 1s → 2 → 4 → 8 → 30s cap; reset to 800ms on a clean Hello (matches the gateway's default).
- On reconnect, prefer `deviceToken` over the shared gateway `token`.
- Heartbeat: client sends `last-heartbeat` if the socket has been idle > 20 s.
- Backpressure: outbound queue capped at 64 frames; surplus rejects with a `Result.err`.

## 6. Onboarding

Onboarding looks different across slices. Slice 1 ships a stripped-down dev pair; slice 2 replaces it with the proper account flow.

### 6.1 Slice 1 — manual pairing (developer / internal testing)

A single form, no account, no provisioning service. **This same form is reused in slice 3 as the BYO path for power users.**

1. **Welcome.** Logo, tagline, two CTAs: *Connect to my OpenClaw* / *Learn more*.
2. **Pair form.** Two fields: gateway URL (e.g. `ws://192.168.1.10:18789`) and gateway token (from the user's `.env`). Hint text explains. *Connect* button.
3. **Connecting.** Spinner + *"Pairing this device…"* — runs the device-proof signing + `connect` round-trip.
4. **Ready.** Big check, *"You're in"*, *Start talking* → home screen.

The shared gateway token is held only long enough to receive the Hello with a `deviceToken`, then discarded; subsequent connects use the `deviceToken` only.

### 6.2 Slice 2 — full sign-up / sign-in (production onboarding)

Replaces slice 1's manual pair. Four frames:

1. **Welcome.** Logo, tagline ("Your private AI assistant. Talks, types, remembers."), two CTAs: *Create account* / *I already have one*.
2. **Sign up / Sign in.** Email + password (+ display name on sign up). *Forgot password* link. Hits the **provisioning service**.
3. **Provisioning.** Animated ring + checklist: ✓ Created your account · ⋯ Spinning up your assistant · ○ Linking this device. *"This takes about 30 seconds the first time."*
4. **Ready.** Same "You're all set" frame as slice 1.

### 6.3 What happens behind the scenes during slice 2 provisioning

Invisible to the user; the Flutter app executes:

1. POST credentials to the provisioning service.
2. Service creates the user's agent container (whichever agent type), returns `{agentType, wsUrl, bootstrapToken}`.
3. App generates a device keypair (ECDSA P-256), stores in secure storage.
4. App picks the matching `GatewayClient` impl based on `agentType`, connects with the bootstrap token + device proof.
5. Gateway returns Hello with a long-lived `deviceToken`.
6. App persists `deviceToken`, discards bootstrap token.
7. From there: app talks directly to the agent via WS. The provisioning service is only contacted for account / billing / agent-lifecycle operations.

Sign-in for an existing user is the same path minus account creation. If the device already has a `deviceToken` for that account, no bootstrap exchange is needed — go straight to gateway connect.

### 6.4 Runtime permissions (all slices)

Two permissions matter on Android (iOS analogous):

- **Microphone (`RECORD_AUDIO`)** — requested only the first time the user taps the mic in Speech Mode (not at app launch). On deny, Speech Mode shows the *Microphone is off* state (§15.2) with a button that deeplinks to the OS app-settings page.
- **Internet (`INTERNET`, normal permission, no prompt)** — declared in the manifest.

Wake word adds a second mic-permission moment when enabled in Settings (slice 1, off by default) — same UX pattern.

If the user permanently denies the mic, the rest of the app (Chat Mode, sessions, settings) keeps working.

## 7. Data model

Mirror the gateway's shape. Don't invent client-side schemas.

```dart
class Session {
  String id;
  String title;
  DateTime updatedAt;
  bool pinned;            // local-only flag if gateway doesn't store it
  bool hasVoiceMessages;
  bool isCron;            // hidden by default per chat.hideCronSessions
}

enum Role { user, assistant, system, tool }
enum MessageSource { typedChat, spokenChat }
enum StreamingState { none, partial, final_, failed }

class ContentPart { /* text, media, reply, voice-directive */ }

class Message {
  String id;
  String sessionId;
  Role role;
  String? text;
  List<ContentPart> parts;
  DateTime createdAt;
  MessageSource source;
  StreamingState streaming;
  ToolCall? toolCall;
}
```

**Local cache** (sqflite): only `sessions` (id, title, updatedAt, pinned) and a tail of the last N messages per session. Used for: cold-start sidebar render and last-known-view if offline. Not authoritative.

## 8. Chat Mode

UX flow: **swipe up from voice home** → message thread + composer (with mini mic on the left). Sessions list is reached by **swipe right** from either home or chat (§14), not as a persistent drawer inside chat.

- **Composer:** mini mic (left) + multi-line text field + send button. Attach button is **deferred** — not present in slice 1, design-space reserved for media uploads in a later slice.
- **Send:** optimistic insert with `streaming: partial`, fire `chat.send` RPC, replace with server-confirmed message on `res.ok` / event.
- **Streaming render:** append to the latest assistant bubble as streaming events arrive. Smooth fade-in for new tokens. Riverpod `select` scopes rebuilds to the active bubble only.
- **Abort:** "Stop generating" button while assistant is streaming → fires `chat.abort` with the response id.
- **Quick actions and 👍/👎 feedback are deferred** (slice 6 launch readiness). Slice 1 ships clean send / receive / abort / sources only.

### 8.1 Chat Mode flow

```
USER             UI                     GATEWAY
 │                │                       │
 │ types + Send   │                       │
 │ ─────────────► │ insert user bubble    │
 │                │ ─── chat.send req ──► │
 │                │                       │ (AI generating)
 │                │ ◄── stream event ─── │
 │                │ ◄── stream event ─── │
 │                │ append tokens to      │
 │                │  assistant bubble     │
 │                │ ◄── final event ──── │
 │                │ mark assistant final  │
 │                │                       │
 │ tap Stop       │ ─── chat.abort req ──►│
 │ ─────────────► │ mark partial stopped  │
```

Stream-event names (e.g. `chat.delta`, `chat.message`) are placeholders — the exact names are locked in task 1 of the implementation plan (§19).

### 8.2 Message rendering

AI replies routinely contain markdown (bullets, bold/italic, headings, links) and code blocks. Plain `Text` widgets won't cut it.

- **Renderer:** `flutter_markdown` for prose; `flutter_highlight` for fenced code blocks (with copy-to-clipboard button).
- **Streaming + markdown:** parse and render incrementally — incomplete fences mid-stream render as plain monospace until the closing fence arrives.
- **Speech Mode interaction:** when TTS speaks a markdown message, **strip markdown syntax first** (don't read "asterisk asterisk hello asterisk asterisk"). A small markdown-to-plain converter sits between `Message.text` and `flutter_tts`.
- **Tables, math, images:** out of scope for slice 1 — render as raw text. Revisit in launch readiness (slice 6).

### 8.3 Tool calls (rendered as sources)

The gateway emits tool/command events mid-response (`chat.toolCallsToggle`, `command.executeLocal`). The user shouldn't see "tool calls"; they should see *what the AI looked at*.

- **While running:** a quiet *"Looking it up…"* line with three dots, between user and AI bubbles.
- **When finished:** the AI bubble appears, with one small pill underneath: *"📎 3 sources ▾"*. If no tools ran, no pill.
- **Tap the pill:** a bottom sheet slides up showing each source as a row (title + domain). Tap a row → opens that source in the browser. Drag down or tap outside → dismisses.
- **Failed fetches drop quietly** — no red error pills. (If *all* fetches fail and the AI can't answer, that surfaces as a normal AI message: "I couldn't reach those — want me to try again?")
- **No raw function names ever** — "searched the web," not "`web.search()`". The mapping from gateway tool name → user-facing label is a small lookup table in `domain/models`.

The exact event payload shape for tool calls is locked in task 1 of the implementation plan.

## 9. Speech Mode

### 9.1 STT/TTS strategy — on-device only

**Decision: phone transcribes locally. Agents only ever see text.**

Flow per voice turn:
1. Phone captures voice through the mic.
2. Phone transcribes on-device (`speech_to_text`, already in the POC).
3. Phone sends the recognized **text** to the agent (same `sendMessage` path as Chat Mode).
4. Agent replies with text.
5. Phone speaks the reply (`flutter_tts`).

**Why on-device only:**
- All three agents (OpenClaw / Nanobot / Zeroclaw) accept text — server-side audio (Talk Mode) would only work on agents that support it, defeating the point of pluggability.
- The existing POC already works this way; we lift the logic into a service rather than redesigning it.
- Lower latency for short turns, fewer bytes on the wire, partial offline capability.

**Talk Mode (server-side audio) is dropped from the roadmap.** We can revisit only if a specific agent makes it strictly better, and only for that agent.

### 9.2 UI states (state machine)

```
       ┌──────────┐                    ┌────────────┐
       │   idle   │ ─── tap mic ──►   │ listening  │
       └──────────┘                    └─────┬──────┘
            ▲                                │ final transcript
            │                                ▼
       ┌──────────┐                    ┌────────────┐
       │responding│ ◄─── chat result ─┤ processing │
       └──────────┘                    └────────────┘
            │
            │ tap mic / "Stop"        ┌────────────┐
            └──────── interrupt ─────►│   idle     │
                                      └────────────┘
```

- **idle:** subtle pulse animation (current 1 s reverse-repeat `AnimationController`).
- **listening:** waveform from `_normalizedSoundLevel` (current logic). Live partial transcript under the ring.
- **processing:** "thinking" dots while waiting on the `chat.send` round-trip.
- **responding:** TTS speaking, **karaoke-style word highlight** via `flutter_tts.setProgressHandler` (Android emits per-word boundaries; iOS does too — fall back to per-sentence on platforms where boundary fidelity is poor).

### 9.3 Interrupt / voice commands

- Tap mic ring while `responding` → stop TTS, start listening.
- Voice keywords during TTS: `"Stop"`, `"Cancel"`, `"Repeat"`. We **keep STT running with low priority during TTS** for keyword detection; recognized intent triggers an action. The current "STT/TTS mutual exclusion" rule from `CLAUDE.md` is preserved for the *primary* listening path; this keyword path is the one documented exception.
- `"Repeat"` → re-speak the last assistant message from local buffer.
- `"Cancel"` → fire `chat.abort` for the in-flight response.

### 9.4 Subtitles

Subtitle area below the ring shows the current TTS line, with per-word highlight tracked from the boundary handler.

## 10. Wake word

| Option | Choice |
|---|---|
| Picovoice Porcupine | **Chosen** for slice 1 (off by default). Excellent quality, on-device, custom keyword "Hi OpenClaw" / "Hey OpenClaw", free for personal/dev use. **Commercial production distribution requires a paid Picovoice license** — budget item before public release. |
| openWakeWord (ONNX) | Backup if Picovoice licensing becomes an issue. |
| Always-on STT loop | Rejected (battery + privacy disaster). |

- Default off. User opts in via Settings → Wake word.
- Cooldown: Porcupine handles internal debouncing; our wrapper enforces a 2s gate after each trigger.
- Manual fallback (mic button) is always available — wake word is an opt-in convenience, not a requirement.
- **Wake word listens only in Speech Mode.** It is fully suspended whenever Chat Mode is active (the phone is not always listening).

## 11. Sessions UX

- **List item:** title, last-message preview, timestamp, pin badge, voice/text indicator (🎙 vs 💬). No unread dot in slice 1.
- **Live updates:** `sessions.subscribe` keeps the list in sync; we update via the events stream.
- **Search:** client-side fuzzy match on titles + cached preview text in slice 1; promote to a server method if `chat.search` (or similar) is found during impl.
- **Filter chips:** All / Voice / Text / Pinned.
- **Actions:**
  - Rename → `sessions.patch {id, title}`
  - Delete → `sessions.delete {id}`
  - Pin → local-only flag stored in cache (until/unless gateway exposes it as a session field).
- **Cron sessions:** the gateway's existing `chat.hideCronSessions` event is honored — show a Settings toggle to mirror the SPA behavior.

## 12. Personalization

Slice 1:
- **Voice picker:** existing `_voiceScore` ranking (WaveNet/Neural/Studio/Premium/Journey > SeaNet/TPF > default/local/embedded), capped at 10, surfaced under Settings → Voice & speech.
- **Tone:** Casual / Professional / Concise. Stored locally; prepended as a hidden hint to the user message. If a server-side tone parameter shows up during impl, switch to it.
- **STT/TTS language:** existing language picker; default from system locale.

Slice 6 (launch readiness — explicitly out of slice 1):
- **Theme:** Material 3 dynamic color, light/dark/system.
- **UI language:** Flutter `intl` / `flutter_localizations`. Slice 1 hard-codes English; slice 6 lights up the rest.

Always delegated to gateway:
- **Model language** (the assistant's reply language) — controlled server-side.

## 13. Plugins / commands

The gateway already exposes `tools.catalog`, `tools.effective`, and `skills.{search,detail,install,status,update}`. Mobile renders these as:

- A **slash menu** in the composer (`/` triggers a list of available commands/skills).
- A **quick-action drawer** with the most-used items.
- Skills/plugins UI ships in slice 6 (launch readiness). Slice 1 has no plugin browse / slash-command menu.

Mobile does not run plugins itself; it's a UI over the gateway's plugin runtime.

## 14. Mode switching (gesture-driven)

The app has a **voice-first home**. Speech Mode *is* the home screen. Chat Mode is reached by gesture, not by toggle.

- **Home (Speech Mode):** mic ring is the hero. Header shows *OpenClaw* (or current session title), `≡` for sessions on left, `⚙` for settings on right.
- **Swipe up** from home → **Chat Mode** for the same session. Mic shrinks into a small icon at the left of the composer (mini-mic in composer pattern).
- **Swipe down** from chat → returns to Speech Mode home.
- **Swipe right** from home or chat → **Sessions list** drawer.
- Both modes consume the same `messages_provider` for the same session. Mode is purely about which input widget is mounted and whether incoming assistant messages auto-play TTS.
- Switching modes never resets, fetches, or loses state.
- Last-used mode is remembered per session (so a session that was started in chat re-opens in chat).

## 15. Error handling / reconnect / offline

- **No connection at startup:** show last-known sessions from cache, banner "Offline — reconnecting…".
- **Mid-session disconnect:** mark in-flight messages `streaming: failed`, offer retry, show banner.
- **`chat.disconnected`:** explicit user-visible state ("This session is open on another client").
- **STT errors:** existing handler preserved (no_match → ignore, network/audio/client → fully stop with snackbar).
- **TTS errors:** snackbar; assistant text bubble still renders.
- **Auth failure:** drop back to onboarding with a specific message; offer "retry with device token" if hinted.
- **Schema validation errors (`INVALID_REQUEST`):** treated as bugs in the client; logged to telemetry, surfaced as a generic "Client out of date — update required" to the user. (This is real — the gateway uses strict JSON schemas; protocol drift is a known failure mode.)

### 15.1 App lifecycle (foreground / background / resume)

| State | WS connection | STT | TTS | Wake word |
|---|---|---|---|---|
| Foregrounded | open, kept alive with heartbeat | active per UI | active per UI | active if enabled + Speech Mode |
| Backgrounded > 30 s grace | gracefully closed | stopped | stopped | stopped |
| Locked screen | same as backgrounded | stopped | stopped | stopped |
| Resumed | reconnect with `deviceToken`; refresh current session | resume on user action | resume on user action | resume if enabled + Speech Mode |

**No background mic capture.** That would require an Android foreground service + a persistent notification — out of scope for slice 1. The wake word listens only while the app is open.

**No queued sends offline.** Thin-client choice (§3): a send while disconnected fails immediately with a retry button. Acceptable because reconnect is fast on a LAN.

### 15.2 Specific UI states (with copy)

| State | When it shows | UI |
|---|---|---|
| **First launch / empty** | No conversations yet | Friendly greeting *"Hi {name}"*, CTA *Tap to talk* + secondary *start typing* |
| **Offline** | Phone has no internet | Top banner *"⚡ No internet — trying to reconnect…"* (persists across screens). Body shows *"You're offline"*, last-seen timestamp. Old sessions still readable from cache. |
| **AI waking up** | Container was idle and shut down; first open after a long pause | Animated dashed ring + *"Waking up your assistant — usually 10–15 seconds"* |
| **Microphone is off** | User denied mic permission, then enters Speech Mode | Body shows *"Microphone is off — to talk, OpenClaw needs the microphone"*, primary CTA *Open Settings*, secondary link *type instead* |
| **Sign-in failed** | Wrong password / network failure (slice 2+) | Inline error on the form: *"That didn't work. Check your password or try again."* |
| **Session deleted on another device** | `chat.disconnected` arrives | Inline notice on the chat thread: *"This conversation was opened on another device."* |

All copy follows the rule: **plain words, no error codes, no jargon, never reference internal protocol terms.**

## 16. Performance / scalability

- **Cold-start target:** ≤ 600 ms to first paint of cached sidebar; ≤ 1.5 s to live socket on Wi-Fi.
- **Streaming render:** Riverpod `select` scopes rebuilds to the active assistant bubble only.
- **Message list:** `ListView.builder` with tuned `cacheExtent`; insertion via `AnimatedList`.
- **Mic visualizer:** existing `AnimationController` (1 s reverse-repeat) drives both mic ring and waveform bars, in both modes.
- **One socket** per app instance, multiplexed across screens.
- **Typing-indicator events** (`chat.thinkingToggle`, `chat.toolCallsToggle`) drive the processing-state UI directly from the gateway — no client-side polling.

## 17. Migration plan from current `lib/main.dart`

Concrete moves (preserving every documented non-obvious behavior in `CLAUDE.md`):

| From `_SttTtsHomePageState` member | New home |
|---|---|
| `_initSpeech`, `_onSpeechStatus`, `_onSpeechError`, `_onSpeechResult`, `_smartFormat`, `_normalizedSoundLevel`, sound-level seed sentinels | `data/voice/stt_service.dart` |
| `_initTts`, `_pickPreferredLanguage`, `_loadVoicesForLanguage`, `_pickPreferredVoice`, `_voiceScore`, `_voiceKey`, voice maps | `data/voice/tts_service.dart` |
| `_userWantsToListen`, `_hasReceivedFinalResult`, restart-loop on `done` status | `data/voice/stt_service.dart` (rule preserved verbatim — both flags retained) |
| STT/TTS mutual exclusion ordering | `data/voice/voice_coordinator.dart` (one place, called by both services) |
| `_pulseController` + waveform math + `_waveBars` | `ui/widgets/voice_visualizer.dart` |
| Bottom text-field area | replaced by `ui/chat/chat_composer.dart` (chat mode) and `ui/speech/speech_input.dart` (speech mode) |
| `_speechRate=0.56`, `_pitch=1.10`, `pauseFor=3s`, `listenFor=2min`, `ListenMode.dictation`, `autoPunctuation: true` | `data/voice/voice_constants.dart` (single file, comment-explained) |
| `_initAll()` post-frame init | `main.dart` bootstrap → providers eagerly initialize |

Everything documented in `CLAUDE.md` § "Key behaviors" carries forward. The single-file shape from the POC is **not** preserved — `CLAUDE.md`'s own guidance (§ Architecture) said decide explicitly when adding features. We're deciding to extract.

## 18. Slices (sequenced delivery)

| Slice | Scope | Code areas |
|---|---|---|
| **1. Core app (OpenClaw, end-to-end, polished)** | Everything that makes the app feel like a finished product *for OpenClaw users*: project restructure into proper layers, every screen from §22, manual pairing onboarding (URL + token — dev only), full `GatewayClient` interface + OpenClaw impl (device proof, reconnect, all chat/sessions methods), chat mode end-to-end (streaming, abort, history, markdown, sources pill), voice mode end-to-end with all polish (4 states, live transcript, karaoke per-word subtitle highlight, voice command interrupts "Stop"/"Repeat"/"Cancel", voice picker, tone selector), **wake word** ("Hi OpenClaw" via Picovoice — opt-in toggle, default off), sessions list (search, filter, pin, rename, delete), settings shell (manual pair info, voice/tone, wake word toggle, privacy/about — **no** Account or Theme rows), error and empty states with proper copy. **No back-end dependencies, no other agents, no themes, no accounts.** | `core/`, `data/gateway/` (interface + `agents/openclaw/`), `data/voice/` (stt, tts, visualizer, wake word), `data/secure/`, `data/cache/`, `state/`, `ui/*` |
| **2. Account onboarding + provisioning service** | Replace manual pairing with proper sign-up / sign-in. Provisioning service integration (HTTP client). The "Setting up your AI" provisioning state. Real per-user agents. The manual-pair form moves to settings as the seed of "BYO." | `data/provisioning/` (HTTP), `ui/onboarding` (sign-up + sign-in flows), `state/auth` |
| **3. Trial + paywall + Stripe + BYO** | Trial countdown banner, "trial ended" lock-out screen, paywall, Stripe payment (web flow on iOS to dodge the App Store cut), BYO agent setup screen reused from slice 1's manual pair, Settings → Agent section. | `ui/billing`, `ui/onboarding/byo`, `data/billing`, `state/subscription` |
| **4. Nanobot agent** | Implement `GatewayClient` for Nanobot. Capabilities flag drives UI feature visibility. Blocked on Nanobot back-end completing. | `data/gateway/agents/nanobot/` |
| **5. Zeroclaw agent** | Same as slice 4 for Zeroclaw. Blocked on Zeroclaw back-end completing. | `data/gateway/agents/zeroclaw/` |
| **6. Launch readiness** | Theme switcher (light / dark / system), multi-language UI, accessibility audit, app icon, privacy policy URL, store listings, crash reporting, install/update skills, plugin/command UX (slash menu, quick-actions). | scattered |

**Slice 1 has zero back-end dependencies** — it runs against your local OpenClaw and is a fully-featured single-agent app on its own. Each subsequent slice unblocks once its specific dependency lands.

## 19. Implementation-time verification tasks

### Blocking slice 1 (must happen before chat UI is wired)

1. **Replay one full SPA→gateway exchange** (Chrome devtools → WS frames) and capture exact JSON shapes for: `chat.send` params, the streaming response event name(s) and payload, `chat.history` page shape, `sessions.list` and `sessions.subscribe` event payloads. Document in a sibling `2026-04-29-openclaw-mobile-protocol-capture.md`.
2. **Implement and verify ECDSA P-256 device-proof signing** matching the gateway's `Gn` / `Mn` / `nt` exactly (canonical-string format is byte-for-byte sensitive). Verified by performing a successful `connect` round-trip from Dart and receiving a Hello with a `deviceToken`.

### Blocking slice 2 (not slice 1)

3. **Lock the provisioning-service API contract** with the back-end team. Endpoints needed: `POST /accounts` (sign up, starts trial), `POST /sessions` (sign in), `GET /me/agent` (returns `{agentType, wsUrl, bootstrapToken?, trialEndsAt?}`), `POST /me/devices`, `DELETE /me/account`, `POST /me/password-reset`. The response includes `agentType` so the app picks the right `GatewayClient` impl. Document in `2026-04-29-openclaw-mobile-provisioning-api.md`.

### Blocking later slices

- Nanobot wire format → slice 5
- Zeroclaw wire format → slice 6
- Stripe specifics + App Store policy strategy → slice 3

## 20. Security posture

- The shared `OPENCLAW_GATEWAY_TOKEN` is never persisted on-device after first successful pair.
- `deviceToken` and the device private key live in `flutter_secure_storage` (Android Keystore / iOS Keychain backed). Never logged, never in error messages.
- Per-device keypairs mean device revocation is real (`device.token.revoke`).
- The gateway today is on `127.0.0.1` (host-network Docker). Once mobile reaches it across a LAN, `wss://` + a self-signed cert (or a tunnel) is required. Out of scope for slice 1; the connection layer is TLS-ready.
- No external telemetry or analytics in-app. Logs stay on device.

## 21. Out-of-scope / explicitly deferred

- Web/desktop targets.
- Full offline-first mirror sync.
- Offline send queue. A send made while disconnected fails immediately with a retry button (§15.1).
- Inline media generation (image/audio attachments to user messages).
- Tables / math rendering / inline images in markdown — later slice.
- Multi-user accounts on the same install.
- Accessibility polish (large-text scaling, screen reader labels, contrast audit) — later slice.
- Build flavors / CI pipeline (dev provisioning service vs prod, signed releases) — set up alongside first external release.
- Android share intent ("Share to OpenClaw" from other apps) — later slice bonus.
- Foreground service for background wake-word — explicitly not pursued.
- Push notifications (FCM/APNs) when not foregrounded — could revisit later once each agent's equivalent of `sessions.subscribe` is solid.
- **Talk Mode (server-side audio pipeline) — explicitly dropped** (§9.1). Voice = on-device STT + on-device TTS, agent only sees text.

## 22. Visual design language (decided in brainstorm)

The visual decisions made during the UI/UX brainstorm. Wireframes are saved under `.superpowers/brainstorm/.../content/` for reference.

### 22.1 Vibe — Dark / Futuristic

- **Primary background:** radial gradient `#1c2a4a → #0a0e1a` (deep navy at top, near-black at bottom).
- **Surface (panels, cards, sheets):** `#0e1424` with `rgba(120,180,255,0.06)` overlay tint.
- **Primary accent:** `#6cb0ff` (electric blue) — used for the mic ring glow, primary buttons, link/highlight color, sources pill border.
- **Accent secondary:** `#8a7aff` (violet) — used in profile-card gradient and onboarding logo.
- **Text:** `#e8eeff` (titles), `#d6e2ff` (body), `#8aa3d4` (subtitle/secondary), `#5a6886` (tertiary/metadata).
- **Status:** `#5cd99a` (green/live), `#ffb86c` (warning/offline), `#ff7a85` (error/danger).
- **Glow:** mic ring uses `box-shadow: 0 0 28px rgba(80,140,255,.55), inset 0 0 18px rgba(80,140,255,.35)` when active.

### 22.2 Layout pattern — Voice-first home

- **Home = Speech Mode.** Mic ring is centered, takes the visual weight.
- **Header:** `≡` (sessions) — Title — `⚙` (settings).
- **Gestures:** swipe up → chat mode (same session), swipe right → sessions list, swipe down (in chat) → back to home.
- **Chat composer** has a mini mic on the left, then the text field, then send. Tap mic in chat → instant voice for that turn.

### 22.3 Voice states (4)

| State | Ring | Animation | Status copy |
|---|---|---|---|
| Idle | Soft 2px outline, dim | Calm, flat waveform | *"Tap to talk"* / *"or say 'Hi OpenClaw'"* |
| Listening | Bright 3px ring, glowing | Slow pulse + live waveform | *"Listening…"* / *"Tap to stop"* + partial transcript |
| Thinking | Dashed ring, slow rotate | Three blinking dots | *"Thinking"* + faded prior transcript |
| Speaking | Solid bright ring | Subtitle line karaoke-highlights current word | *"Speaking"* / *"Tap to stop · say 'Repeat'"* |

### 22.4 Component decisions

- **Sessions list:** Pinned section first, then Recent. Search bar + filter chips (All / Voice / Text / Pinned). Voice rows show 🎙, text rows show 💬. Avatar + ⚙ in the bottom bar.
- **Settings (slice 1):** Pair info row (gateway URL, last connected — read-only), Voice & speech (voice picker, speaking rate, wake word toggle, language), Personality (tone), Privacy & data (clear cache, unpair), Help & About (support link, version). **No** Account section, **no** Theme picker, **no** App language picker (slice 6 launch readiness).
- **Tool calls:** Quiet *"📎 N sources ▾"* pill under each AI bubble. Tap → bottom sheet with the source list. No tool calls in any other form.
- **Markdown:** rendered with `flutter_markdown` (prose) + `flutter_highlight` (code). Stripped to plain before TTS speaks.
- **Empty / error states:** plain-words copy, single CTA per screen, no error codes.

## 23. Testing strategy

Three layers, each with a clear scope:

| Layer | What it covers | Tools | When it runs |
|---|---|---|---|
| **Unit** | Envelope encode/decode, request/response correlation, device-proof signing canonical string, reconnect backoff, markdown-to-plain conversion, voice-state machine, sound-level normalization | `flutter_test` | every change; fast |
| **Widget** | Chat composer, message bubbles, streaming render, sessions list, mic visualizer, onboarding form | `flutter_test` + golden tests for visual states | every change; fast |
| **Integration** | Real `connect` round-trip against a locally running gateway; full chat send + receive + abort; reconnect after socket close | Dart test driver against a disposable Docker gateway | nightly + before merging slice work |

**Manual QA checklist** (executed before declaring a slice done): pair the phone, send a chat, observe streaming, abort mid-response, kill the gateway and watch reconnect, deny mic permission and verify graceful UX, switch to chat mode and confirm wake word stops.

**No mocks for the gateway** in integration tests — the gateway is the source of truth and protocol drift is a real failure mode (§15). Mocking it would let the same bugs that bit us in real usage pass tests. Instead, integration tests run against the actual `ghcr.io/openclaw/openclaw` image pinned to the version in `.env`.
