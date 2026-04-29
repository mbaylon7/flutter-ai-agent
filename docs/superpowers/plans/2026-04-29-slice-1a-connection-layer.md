# Slice 1A — Connection Layer + Manual Pair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Flutter app connect to a running OpenClaw gateway via a manual *paste-URL-and-token* form, with full ECDSA P-256 device-proof signing matching the SPA's wire protocol byte-for-byte. End state: paste credentials → see "You're in" → connection stays alive with reconnect.

**Architecture:** A pluggable `GatewayClient` interface with one implementation (`OpenClawGatewayClient`). The WebSocket connection lives in a single `WsConnection` class with reconnect/heartbeat. A typed envelope codec correlates `req`/`res` and routes `event` frames into typed streams. **Device identity is an Ed25519 keypair (32-byte secret + 32-byte public); `deviceId` is the lowercase hex of SHA-256(publicKey)**. All persisted in `flutter_secure_storage`. Riverpod 2.x manages app-wide connection state.

**Tech Stack:** Flutter 3.10+, Dart 3.x, Riverpod 2.5+, `web_socket_channel`, **`cryptography` (Ed25519 sign + SHA-256)**, `flutter_secure_storage`, `uuid`, `sqflite`, `flutter_test`.

**Source of truth for every JSON shape and crypto detail:** `docs/superpowers/specs/2026-04-29-openclaw-mobile-protocol-capture.md`. Where this plan and that doc disagree, the capture doc wins.

---

## File Structure

| Path | Responsibility |
|---|---|
| `pubspec.yaml` | Dependencies |
| `lib/main.dart` | Bootstrap, ProviderScope, root MaterialApp |
| `lib/app.dart` | Routing + theme |
| `lib/core/logger.dart` | Tagged logger (debug/info/warn/error) |
| `lib/core/result.dart` | `Result<T, E>` sealed class for fallible ops |
| `lib/core/ids.dart` | UUID v4 + persistent instance id helpers |
| `lib/core/theme.dart` | Dark/futuristic Material 3 theme tokens (per spec §22.1) |
| `lib/data/secure/secure_store.dart` | Wrapper around `flutter_secure_storage` |
| `lib/data/gateway/shared/ws_connection.dart` | Raw WS lifecycle, reconnect, ping |
| `lib/data/gateway/shared/envelope_codec.dart` | JSON in/out, req/res correlation, event routing, seq tracking |
| `lib/data/gateway/shared/device_identity.dart` | ECDSA P-256 keypair gen + persistent storage |
| `lib/data/gateway/gateway_client.dart` | Abstract `GatewayClient` interface |
| `lib/data/gateway/connection_config.dart` | `ConnectionConfig` data class |
| `lib/data/gateway/agents/openclaw/canonical.dart` | Canonical-string builder for device-proof signing |
| `lib/data/gateway/agents/openclaw/device_proof.dart` | Sign canonical with private key, return SPKI + signature |
| `lib/data/gateway/agents/openclaw/connect_params.dart` | Build the `connect` RPC params object |
| `lib/data/gateway/agents/openclaw/openclaw_client.dart` | `OpenClawGatewayClient implements GatewayClient` |
| `lib/state/connection_provider.dart` | Riverpod provider exposing connection state + client |
| `lib/state/pair_provider.dart` | Drives the manual-pair flow |
| `lib/ui/onboarding/welcome_screen.dart` | First frame of pair flow |
| `lib/ui/onboarding/pair_form_screen.dart` | URL + token form |
| `lib/ui/onboarding/connecting_screen.dart` | Spinner while connect runs |
| `lib/ui/onboarding/ready_screen.dart` | Success → home (placeholder until 1B) |
| `lib/ui/widgets/oc_button.dart` | Primary/secondary buttons matching theme |
| `lib/ui/widgets/oc_text_field.dart` | Themed text field |
| `docs/superpowers/specs/2026-04-29-openclaw-mobile-protocol-capture.md` | Captured WS traffic + JSON shapes |
| `test/data/gateway/shared/envelope_codec_test.dart` | Codec unit tests |
| `test/data/gateway/agents/openclaw/canonical_test.dart` | Canonical-string golden tests |
| `test/data/gateway/agents/openclaw/device_proof_test.dart` | Sign/verify tests |
| `test/data/gateway/agents/openclaw/openclaw_client_integration_test.dart` | Real connect against running gateway |

---

## Phase 0 — Pre-flight verification (blocking)

These two tasks unblock everything else. Do not write a single chat-related line until both are green.

### Task 0.1: Replay one full SPA→gateway exchange and document JSON shapes

**Files:**
- Create: `docs/superpowers/specs/2026-04-29-openclaw-mobile-protocol-capture.md`

- [ ] **Step 1: Open the SPA in Chrome with DevTools**

Run:
```bash
docker ps --format '{{.Names}}\t{{.Status}}'  # confirm openclaw-marvin is running
```
Open `http://127.0.0.1:18789/` in Chrome. Open DevTools (F12) → Network tab → filter "WS" → click the WebSocket connection → "Messages" sub-tab.

- [ ] **Step 2: Capture handshake**

Reload the SPA so a fresh handshake happens. Copy the first few frames into the doc:
- The `connect.challenge` event from server (`{"type":"event","event":"connect.challenge","payload":{"nonce":"…","ts":…}}`)
- The client's `connect` request (`{"type":"req","id":"…","method":"connect","params":{…}}`) — full params verbatim
- The server's response (`{"type":"res","id":"…","ok":true,"result":{…}}`) — full Hello payload

- [ ] **Step 3: Capture chat round-trip**

In the SPA, open a new chat, send the message *"Reply with the single word: pong"*. Capture every WS frame from the moment of send to the final response:
- The `chat.send` request (note exact `params` shape: `{sessionId, text, …}`)
- All streaming events that follow (likely `chat.delta` / `chat.message` / `chat.toolCallsToggle` / `chat.refreshTitle` — names + payloads as they actually arrive)
- The terminating event (likely `chat.message` with `final:true` or similar)

- [ ] **Step 4: Capture sessions list**

Reload, watch the WS frames during initial render. Capture:
- The `sessions.list` request and response shape
- The `sessions.subscribe` request and any pushed `sessions.*` events

- [ ] **Step 5: Capture history load**

Click an existing session in the SPA. Capture the `chat.history` request and response shape (paginated? cursor field?).

- [ ] **Step 6: Capture abort**

Send a long message ("Write me a 500-word essay on llamas") and tap the SPA's Stop button mid-stream. Capture the `chat.abort` request shape.

- [ ] **Step 7: Document everything**

In `2026-04-29-openclaw-mobile-protocol-capture.md`, write one section per captured exchange. Each section: title, a JSON code block of the exact frame, and a paragraph of notes (e.g. *"`seq` increments per event, monotonic per connection"*). This file is the source of truth for plans 1B and beyond.

- [ ] **Step 8: Commit**

```bash
git add docs/superpowers/specs/2026-04-29-openclaw-mobile-protocol-capture.md
git commit -m "docs: capture OpenClaw WS protocol traffic"
```

---

### Task 0.2: Implement and verify ECDSA P-256 device-proof signing in Dart

**Files:**
- Create: `tool/verify_device_proof.dart` (one-off verification script)

This task spikes the hardest piece *before* we touch app code. The canonical-string format from `nt()` in the SPA bundle must be matched exactly. We write a standalone Dart script that connects to the running gateway, sends a real `connect` request with a valid signature, and prints the Hello response.

- [ ] **Step 1: Add `cryptography` and `web_socket_channel` to `tool/` workspace**

If there's no separate dev-dependencies setup yet, add to root `pubspec.yaml` `dev_dependencies`:
```yaml
dev_dependencies:
  cryptography: ^2.7.0
  web_socket_channel: ^3.0.0
  uuid: ^4.5.0
```
Run:
```bash
flutter pub get
```

- [ ] **Step 2: Read the SPA bundle for the canonical function**

From the earlier brainstorm we know `nt()` builds a canonical string from `{deviceId, clientId, clientMode, role, scopes, signedAtMs, token, nonce}`. Find its exact body in the SPA bundle:
```bash
grep -oE 'function nt\(\w+\)\{[^}]{0,800}' /tmp/oc_assets/index-D0pCc5YA.js | head -1
```
Document the format inline in `tool/verify_device_proof.dart` as a comment so future readers can match the exact JS source.

- [ ] **Step 3: Write the verification script**

Create `tool/verify_device_proof.dart`:
```dart
// Verifies that our Dart canonical-string + ECDSA P-256 signing matches what
// the gateway's `nt()` and signing path expect. Hits a real running gateway.

import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';

const gatewayUrl = 'ws://127.0.0.1:18789/';
const gatewayToken = 'test-123'; // dev token

Future<void> main() async {
  final ws = IOWebSocketChannel.connect(Uri.parse(gatewayUrl));
  final challenge = await ws.stream.first as String;
  print('◀ challenge: $challenge');
  final challengeJson = jsonDecode(challenge) as Map<String, dynamic>;
  final nonce = (challengeJson['payload'] as Map)['nonce'] as String;

  // Generate a P-256 keypair (in real app this is persisted; here we make fresh each run)
  final algo = Ecdsa.p256(Sha256());
  final keypair = await algo.newKeyPair();
  final publicKey = await keypair.extractPublicKey();
  final publicKeyBytes = await publicKey.bytes;
  // Note: gateway expects SPKI/base64. cryptography returns raw 64-byte X||Y.
  // SPKI wrapping is required — see Step 5.

  final deviceId = const Uuid().v4();
  final instanceId = const Uuid().v4();
  final signedAtMs = DateTime.now().millisecondsSinceEpoch;

  // Build canonical string per the gateway's nt() function.
  // FROM SPA bundle nt(): TODO replace this with the exact format extracted in Step 2.
  final canonical = [
    'deviceId=$deviceId',
    'clientId=openclaw-android',
    'clientMode=webchat',
    'role=operator',
    'scopes=operator.admin,operator.read,operator.write,operator.approvals,operator.pairing',
    'signedAtMs=$signedAtMs',
    'token=$gatewayToken',
    'nonce=$nonce',
  ].join('\n');

  final signature = await algo.sign(
    utf8.encode(canonical),
    keyPair: keypair,
  );

  // Build connect request
  final connectReq = {
    'type': 'req',
    'id': const Uuid().v4(),
    'method': 'connect',
    'params': {
      'minProtocol': 3,
      'maxProtocol': 3,
      'client': {
        'id': 'openclaw-android',
        'version': '0.0.1',
        'platform': 'linux',
        'mode': 'webchat',
        'instanceId': instanceId,
      },
      'role': 'operator',
      'scopes': [
        'operator.admin', 'operator.read', 'operator.write',
        'operator.approvals', 'operator.pairing',
      ],
      'device': {
        'id': deviceId,
        'publicKey': base64Encode(publicKeyBytes), // PROBABLY needs SPKI wrap
        'signature': base64Encode(signature.bytes),
        'signedAt': signedAtMs,
        'nonce': nonce,
      },
      'caps': ['tool-events'],
      'auth': {'token': gatewayToken},
      'userAgent': 'oc-verify/0.1',
      'locale': 'en-US',
    },
  };

  print('▶ ${jsonEncode(connectReq)}');
  ws.sink.add(jsonEncode(connectReq));

  await for (final frame in ws.stream.timeout(const Duration(seconds: 5))) {
    print('◀ $frame');
  }
}
```

- [ ] **Step 4: Run it and observe failure**

Run:
```bash
dart run tool/verify_device_proof.dart
```
Expected first run: `INVALID_REQUEST` with a schema-validation error pointing at `/device/publicKey` or `/device/signature`. The error message *itself* tells you what's wrong — read it carefully.

- [ ] **Step 5: Fix the public-key encoding to SPKI**

The gateway expects an X.509 SubjectPublicKeyInfo (SPKI) DER-encoded base64, not the raw X||Y point. Update the script:
```dart
// SPKI wrapping for P-256 (NIST curve, OID 1.2.840.10045.2.1; named curve 1.2.840.10045.3.1.7)
const _spkiPrefix = <int>[
  0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86,
  0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
  0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
  0x42, 0x00, 0x04,
];
List<int> toSpki(List<int> rawXY) => [..._spkiPrefix, ...rawXY];

// In main():
final publicKeyBytes = await publicKey.bytes; // raw 64 bytes
final spki = toSpki(publicKeyBytes);
'publicKey': base64Encode(spki),
```

- [ ] **Step 6: Run again, iterate on canonical string until Hello arrives**

```bash
dart run tool/verify_device_proof.dart
```
If the response is `AUTH_TOKEN_MISMATCH` or a generic signature-rejected error, the canonical string format is off. Use the bundle's `nt()` definition (extracted in Step 2) as the source of truth. Common gotchas:
- separator (newlines vs `|` vs `&`)
- field ordering
- `null` vs empty string for absent token
- sorting of scopes vs preserving order

Iterate until you see `{"type":"res","id":"…","ok":true,"result":{"auth":{...,"deviceToken":"…"}}}`.

- [ ] **Step 7: Document the working canonical format**

In `2026-04-29-openclaw-mobile-protocol-capture.md`, add a section *"Canonical string format for `nt()`"* with the exact format that produced the Hello. This is what `lib/data/gateway/agents/openclaw/canonical.dart` will be written against.

- [ ] **Step 8: Commit**

```bash
git add tool/verify_device_proof.dart docs/superpowers/specs/2026-04-29-openclaw-mobile-protocol-capture.md pubspec.yaml pubspec.lock
git commit -m "feat: spike device-proof signing, full connect handshake working"
```

---

## Phase 1 — Project setup

### Task 1: Add slice-1A dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add dependencies**

Update `pubspec.yaml` `dependencies`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  speech_to_text: ^7.3.0
  flutter_tts: ^4.2.3

  # Slice 1A
  flutter_riverpod: ^2.5.1
  web_socket_channel: ^3.0.0
  cryptography: ^2.7.0
  flutter_secure_storage: ^9.2.2
  uuid: ^4.5.0
  sqflite: ^2.4.0
  path_provider: ^2.1.4
  collection: ^1.18.0
```

Update `dev_dependencies`:
```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  mocktail: ^1.0.4
```

- [ ] **Step 2: Install and verify**

Run:
```bash
flutter pub get
flutter analyze
```
Expected: no errors. (The current `lib/main.dart` may show some lints; ignore for now — Phase 9 deletes it.)

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add slice-1A dependencies"
```

---

### Task 2: Create folder skeleton

**Files:**
- Create empty placeholder `.gitkeep` files so the structure is committed.

- [ ] **Step 1: Create directories**

Run:
```bash
cd "/media/marvin-baylon/Working Files/cloudesk/stt_tts"
mkdir -p lib/core lib/data/secure lib/data/gateway/shared lib/data/gateway/agents/openclaw lib/state lib/ui/onboarding lib/ui/widgets test/data/gateway/shared test/data/gateway/agents/openclaw test/core
touch lib/core/.gitkeep lib/data/secure/.gitkeep lib/data/gateway/shared/.gitkeep lib/data/gateway/agents/openclaw/.gitkeep lib/state/.gitkeep lib/ui/onboarding/.gitkeep lib/ui/widgets/.gitkeep
```

- [ ] **Step 2: Commit**

```bash
git add lib/ test/
git commit -m "chore: create slice-1A folder skeleton"
```

---

### Task 3: Write `Result<T, E>` sealed class

**Files:**
- Create: `lib/core/result.dart`
- Create: `test/core/result_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/result_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/result.dart';

void main() {
  group('Result', () {
    test('Ok holds value', () {
      const r = Result<int, String>.ok(42);
      expect(r.isOk, true);
      expect(r.isErr, false);
      expect((r as Ok<int, String>).value, 42);
    });

    test('Err holds error', () {
      const r = Result<int, String>.err('boom');
      expect(r.isOk, false);
      expect(r.isErr, true);
      expect((r as Err<int, String>).error, 'boom');
    });

    test('map transforms Ok value', () {
      const r = Result<int, String>.ok(2);
      final mapped = r.map((v) => v * 10);
      expect((mapped as Ok<int, String>).value, 20);
    });

    test('map preserves Err', () {
      const r = Result<int, String>.err('x');
      final mapped = r.map((v) => v * 10);
      expect((mapped as Err<int, String>).error, 'x');
    });

    test('whenOr provides fallback', () {
      const ok = Result<int, String>.ok(5);
      const err = Result<int, String>.err('e');
      expect(ok.whenOr(ok: (v) => v + 1, fallback: -1), 6);
      expect(err.whenOr(ok: (v) => v + 1, fallback: -1), -1);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
flutter test test/core/result_test.dart
```
Expected: compilation errors — `Result` is not defined.

- [ ] **Step 3: Implement `Result`**

Create `lib/core/result.dart`:
```dart
sealed class Result<T, E> {
  const Result();
  const factory Result.ok(T value) = Ok<T, E>;
  const factory Result.err(E error) = Err<T, E>;

  bool get isOk => this is Ok<T, E>;
  bool get isErr => this is Err<T, E>;

  Result<U, E> map<U>(U Function(T) f) => switch (this) {
        Ok(value: final v) => Result<U, E>.ok(f(v)),
        Err(error: final e) => Result<U, E>.err(e),
      };

  R whenOr<R>({required R Function(T) ok, required R fallback}) =>
      switch (this) {
        Ok(value: final v) => ok(v),
        Err() => fallback,
      };
}

final class Ok<T, E> extends Result<T, E> {
  final T value;
  const Ok(this.value);
}

final class Err<T, E> extends Result<T, E> {
  final E error;
  const Err(this.error);
}
```

- [ ] **Step 4: Run test to verify pass**

Run:
```bash
flutter test test/core/result_test.dart
```
Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/result.dart test/core/result_test.dart
git commit -m "feat(core): add Result<T,E> sealed class"
```

---

### Task 4: Write `Logger` (tagged, level-filtered)

**Files:**
- Create: `lib/core/logger.dart`
- Create: `test/core/logger_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/logger_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/logger.dart';

void main() {
  test('Logger filters below threshold', () {
    final lines = <String>[];
    final log = Logger(tag: 'T', minLevel: LogLevel.warn, sink: lines.add);
    log.debug('debug');
    log.info('info');
    log.warn('warn');
    log.error('error');
    expect(lines.length, 2);
    expect(lines[0], contains('[T] WARN warn'));
    expect(lines[1], contains('[T] ERROR error'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
flutter test test/core/logger_test.dart
```
Expected: compile error.

- [ ] **Step 3: Implement**

Create `lib/core/logger.dart`:
```dart
enum LogLevel { debug, info, warn, error }

class Logger {
  Logger({
    required this.tag,
    this.minLevel = LogLevel.info,
    void Function(String)? sink,
  }) : _sink = sink ?? _defaultSink;

  final String tag;
  final LogLevel minLevel;
  final void Function(String) _sink;

  static void _defaultSink(String line) {
    // ignore: avoid_print
    print(line);
  }

  void debug(String msg) => _emit(LogLevel.debug, msg);
  void info(String msg) => _emit(LogLevel.info, msg);
  void warn(String msg) => _emit(LogLevel.warn, msg);
  void error(String msg) => _emit(LogLevel.error, msg);

  void _emit(LogLevel level, String msg) {
    if (level.index < minLevel.index) return;
    _sink('[$tag] ${level.name.toUpperCase()} $msg');
  }
}
```

- [ ] **Step 4: Run test to verify pass**

Run:
```bash
flutter test test/core/logger_test.dart
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/logger.dart test/core/logger_test.dart
git commit -m "feat(core): add tagged Logger"
```

---

### Task 5: Write `ids.dart` helpers

**Files:**
- Create: `lib/core/ids.dart`
- Create: `test/core/ids_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/ids_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/ids.dart';

void main() {
  test('newRequestId returns unique v4 UUIDs', () {
    final a = newRequestId();
    final b = newRequestId();
    expect(a, isNot(b));
    expect(a.length, 36);
    expect(a, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
flutter test test/core/ids_test.dart
```
Expected: compile error.

- [ ] **Step 3: Implement**

Create `lib/core/ids.dart`:
```dart
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newRequestId() => _uuid.v4();
String newDeviceId() => _uuid.v4();
String newInstanceId() => _uuid.v4();
```

- [ ] **Step 4: Run test to verify pass**

Run:
```bash
flutter test test/core/ids_test.dart
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/ids.dart test/core/ids_test.dart
git commit -m "feat(core): add id generation helpers"
```

---

### Task 6: Define theme tokens (matching spec §22.1 dark/futuristic)

**Files:**
- Create: `lib/core/theme.dart`

- [ ] **Step 1: Define the theme**

Create `lib/core/theme.dart`:
```dart
import 'package:flutter/material.dart';

class OcColors {
  static const bgTop = Color(0xFF1c2a4a);
  static const bgBottom = Color(0xFF0a0e1a);
  static const surface = Color(0xFF0E1424);
  static const accent = Color(0xFF6CB0FF);
  static const accent2 = Color(0xFF8A7AFF);
  static const textPrimary = Color(0xFFE8EEFF);
  static const textBody = Color(0xFFD6E2FF);
  static const textSubtitle = Color(0xFF8AA3D4);
  static const textMeta = Color(0xFF5A6886);
  static const live = Color(0xFF5CD99A);
  static const warn = Color(0xFFFFB86C);
  static const danger = Color(0xFFFF7A85);
  static const overlayTint = Color(0x0F78B4FF); // rgba(120,180,255,0.06)
  static const borderTint = Color(0x2978B4FF);  // rgba(120,180,255,0.16)
}

ThemeData ocDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: OcColors.bgBottom,
    colorScheme: ColorScheme.fromSeed(
      seedColor: OcColors.accent,
      brightness: Brightness.dark,
      surface: OcColors.surface,
      primary: OcColors.accent,
      secondary: OcColors.accent2,
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(color: OcColors.textPrimary, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(color: OcColors.textPrimary, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: OcColors.textBody),
      bodyMedium: TextStyle(color: OcColors.textBody),
      bodySmall: TextStyle(color: OcColors.textSubtitle),
      labelSmall: TextStyle(color: OcColors.textMeta, fontSize: 10),
    ),
  );
}

const ocBackgroundGradient = LinearGradient(
  begin: Alignment(0, -1),
  end: Alignment(0, 0.6),
  colors: [OcColors.bgTop, OcColors.bgBottom],
);
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/theme.dart
git commit -m "feat(core): add dark/futuristic theme tokens"
```

---

### Task 7: Bootstrap app with Riverpod and the new theme

**Files:**
- Modify: `lib/main.dart` (replace existing content)
- Create: `lib/app.dart`

- [ ] **Step 1: Write `lib/app.dart`**

Create `lib/app.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/ui/onboarding/welcome_screen.dart';

class OpenClawApp extends StatelessWidget {
  const OpenClawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OpenClaw',
      theme: ocDarkTheme(),
      home: const WelcomeScreen(),
    );
  }
}
```

- [ ] **Step 2: Replace `lib/main.dart`**

Replace `lib/main.dart` with:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/app.dart';

void main() {
  runApp(const ProviderScope(child: OpenClawApp()));
}
```

- [ ] **Step 3: Stub `WelcomeScreen` so the app compiles**

Create `lib/ui/onboarding/welcome_screen.dart`:
```dart
import 'package:flutter/material.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('OpenClaw — slice 1A')));
}
```

- [ ] **Step 4: Verify it builds**

Run:
```bash
flutter analyze
flutter test
```
Expected: no errors. Existing tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/app.dart lib/ui/onboarding/welcome_screen.dart
git commit -m "feat: bootstrap app with Riverpod + dark theme + welcome stub"
```

---

## Phase 2 — Secure storage + device identity

### Task 8: `SecureStore` adapter

**Files:**
- Create: `lib/data/secure/secure_store.dart`
- Create: `test/data/secure/secure_store_test.dart`

- [ ] **Step 1: Write the test (with a fake backing store so we don't hit real Keystore)**

Create `test/data/secure/secure_store_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/secure/secure_store.dart';

void main() {
  test('FakeSecureStore stores and retrieves values', () async {
    final store = FakeSecureStore();
    expect(await store.read('k'), null);
    await store.write('k', 'v');
    expect(await store.read('k'), 'v');
    await store.delete('k');
    expect(await store.read('k'), null);
  });
}
```

- [ ] **Step 2: Run to confirm fail**

Run:
```bash
flutter test test/data/secure/secure_store_test.dart
```
Expected: compile error.

- [ ] **Step 3: Implement adapter + fake**

Create `lib/data/secure/secure_store.dart`:
```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureStore implements SecureStore {
  FlutterSecureStore([FlutterSecureStorage? backing])
      : _backing = backing ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );
  final FlutterSecureStorage _backing;

  @override
  Future<String?> read(String key) => _backing.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _backing.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _backing.delete(key: key);
}

class FakeSecureStore implements SecureStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}
```

- [ ] **Step 4: Run to verify pass**

Run:
```bash
flutter test test/data/secure/secure_store_test.dart
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/data/secure/secure_store.dart test/data/secure/secure_store_test.dart
git commit -m "feat(secure): add SecureStore adapter + fake"
```

---

### Task 9: `DeviceIdentity` (Ed25519 keypair + SHA-256 deviceId)

**Files:**
- Create: `lib/data/gateway/shared/device_identity.dart`
- Create: `test/data/gateway/shared/device_identity_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/gateway/shared/device_identity_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/shared/device_identity.dart';
import 'package:stt_tts/data/secure/secure_store.dart';

void main() {
  test('loadOrCreate generates once, returns same identity on second call', () async {
    final store = FakeSecureStore();
    final manager = DeviceIdentityManager(store: store);
    final a = await manager.loadOrCreate();
    final b = await manager.loadOrCreate();
    expect(a.deviceId, b.deviceId);
    expect(a.publicKeyB64u, b.publicKeyB64u);
    // deviceId is 64 lowercase hex chars (SHA-256 hex of publicKey)
    expect(a.deviceId, matches(RegExp(r'^[0-9a-f]{64}$')));
    // publicKey base64url-no-pad of 32 bytes ⇒ 43 chars, no '='
    expect(a.publicKeyB64u.length, 43);
    expect(a.publicKeyB64u.contains('='), false);
  });

  test('sign produces a 64-byte Ed25519 signature, returned as base64url-no-pad', () async {
    final store = FakeSecureStore();
    final manager = DeviceIdentityManager(store: store);
    final id = await manager.loadOrCreate();
    final sigB64u = await id.signCanonical('hello world');
    // Ed25519 signature is exactly 64 bytes ⇒ 86 chars base64url-no-pad
    expect(sigB64u.length, 86);
    expect(sigB64u.contains('='), false);
  });
}
```

- [ ] **Step 2: Run to confirm fail**

Run:
```bash
flutter test test/data/gateway/shared/device_identity_test.dart
```
Expected: compile error.

- [ ] **Step 3: Implement (Ed25519 + SHA-256-derived deviceId + base64url-no-pad)**

Create `lib/data/gateway/shared/device_identity.dart`:
```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:stt_tts/data/secure/secure_store.dart';

const _kSecret = 'oc.deviceSecret'; // base64url-no-pad of 32 raw bytes
const _kPublic = 'oc.devicePublic'; // base64url-no-pad of 32 raw bytes
const _kDeviceId = 'oc.deviceId';   // 64-char lowercase hex of SHA-256(public)

/// Encodes bytes as base64url WITHOUT padding (matches gateway's En()).
String base64UrlNoPad(List<int> b) =>
    base64Url.encode(b).replaceAll('=', '');

/// Decodes a base64url-no-pad string. Adds back '=' padding before decoding.
Uint8List decodeBase64UrlNoPad(String s) {
  final padded = s + '=' * ((4 - s.length % 4) % 4);
  return base64Url.decode(padded);
}

/// Lowercase hex string (matches gateway's On()).
String hexLower(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

class DeviceIdentity {
  DeviceIdentity._({
    required this.deviceId,
    required this.publicKeyB64u,
    required SimpleKeyPair keyPair,
  }) : _keyPair = keyPair;

  /// 64 lowercase hex chars: `hex(SHA-256(publicKeyBytes))`.
  final String deviceId;

  /// Raw 32-byte Ed25519 public key, base64url-no-pad.
  final String publicKeyB64u;

  final SimpleKeyPair _keyPair;
  static final _algo = Ed25519();

  /// Signs the canonical UTF-8 bytes; returns base64url-no-pad of the
  /// 64-byte raw Ed25519 signature.
  Future<String> signCanonical(String canonical) async {
    final sig = await _algo.sign(
      utf8.encode(canonical),
      keyPair: _keyPair,
    );
    return base64UrlNoPad(sig.bytes);
  }
}

class DeviceIdentityManager {
  DeviceIdentityManager({required this.store});
  final SecureStore store;
  static final _algo = Ed25519();
  static final _sha = Sha256();

  Future<DeviceIdentity> loadOrCreate() async {
    final secB64 = await store.read(_kSecret);
    final pubB64 = await store.read(_kPublic);
    final id     = await store.read(_kDeviceId);

    if (secB64 != null && pubB64 != null && id != null) {
      final secBytes = decodeBase64UrlNoPad(secB64);
      final pubBytes = decodeBase64UrlNoPad(pubB64);
      // Re-derive deviceId and confirm match. If corrupt, regenerate.
      final hash = await _sha.hash(pubBytes);
      final derivedId = hexLower(hash.bytes);
      if (derivedId != id) {
        await _wipe();
        return loadOrCreate();
      }
      final keyPair = SimpleKeyPairData(
        secBytes,
        publicKey: SimplePublicKey(pubBytes, type: KeyPairType.ed25519),
        type: KeyPairType.ed25519,
      );
      return DeviceIdentity._(
        deviceId: id,
        publicKeyB64u: pubB64,
        keyPair: keyPair,
      );
    }
    return _generateNew();
  }

  Future<DeviceIdentity> _generateNew() async {
    final keyPair = await _algo.newKeyPair();
    final secret = await keyPair.extractPrivateKeyBytes();
    final pub = await keyPair.extractPublicKey();
    final pubBytes = await pub.bytes;
    final hash = await _sha.hash(pubBytes);
    final deviceId = hexLower(hash.bytes);
    final pubB64u = base64UrlNoPad(pubBytes);
    final secB64u = base64UrlNoPad(secret);

    await store.write(_kSecret, secB64u);
    await store.write(_kPublic, pubB64u);
    await store.write(_kDeviceId, deviceId);

    return DeviceIdentity._(
      deviceId: deviceId,
      publicKeyB64u: pubB64u,
      keyPair: keyPair,
    );
  }

  Future<void> _wipe() async {
    await store.delete(_kSecret);
    await store.delete(_kPublic);
    await store.delete(_kDeviceId);
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run:
```bash
flutter test test/data/gateway/shared/device_identity_test.dart
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/data/gateway/shared/device_identity.dart test/data/gateway/shared/device_identity_test.dart
git commit -m "feat(gateway): add DeviceIdentity with persistent P-256 keypair"
```

---

## Phase 3 — Envelope codec

### Task 10: Envelope types + JSON encode/decode

**Files:**
- Create: `lib/data/gateway/shared/envelope_codec.dart`
- Create: `test/data/gateway/shared/envelope_codec_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/gateway/shared/envelope_codec_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/shared/envelope_codec.dart';

void main() {
  group('decodeFrame', () {
    test('decodes a request', () {
      final f = decodeFrame('{"type":"req","id":"X","method":"connect","params":{"a":1}}');
      expect(f, isA<ReqFrame>());
      final r = f as ReqFrame;
      expect(r.id, 'X');
      expect(r.method, 'connect');
      expect(r.params, {'a': 1});
    });

    test('decodes an ok response (gateway uses "payload" field)', () {
      final f = decodeFrame('{"type":"res","id":"X","ok":true,"payload":{"hello":"world"}}');
      expect(f, isA<ResFrame>());
      final r = f as ResFrame;
      expect(r.ok, true);
      expect(r.payload, {'hello': 'world'});
      expect(r.error, null);
    });

    test('decodes an error response', () {
      final f = decodeFrame('{"type":"res","id":"X","ok":false,"error":{"code":"X","message":"M"}}');
      final r = f as ResFrame;
      expect(r.ok, false);
      expect(r.error?.code, 'X');
      expect(r.error?.message, 'M');
    });

    test('decodes an event', () {
      final f = decodeFrame('{"type":"event","event":"chat.delta","payload":{"t":"hi"},"seq":7}');
      final e = f as EventFrame;
      expect(e.event, 'chat.delta');
      expect(e.payload, {'t': 'hi'});
      expect(e.seq, 7);
    });
  });

  test('encodeReq serializes the request shape', () {
    final s = encodeReq(id: 'X', method: 'connect', params: {'a': 1});
    expect(s, '{"type":"req","id":"X","method":"connect","params":{"a":1}}');
  });
}
```

- [ ] **Step 2: Run to confirm fail**

Run:
```bash
flutter test test/data/gateway/shared/envelope_codec_test.dart
```
Expected: compile error.

- [ ] **Step 3: Implement**

Create `lib/data/gateway/shared/envelope_codec.dart`:
```dart
import 'dart:convert';

sealed class Frame {
  const Frame();
}

class ReqFrame extends Frame {
  const ReqFrame({required this.id, required this.method, required this.params});
  final String id;
  final String method;
  final Map<String, dynamic> params;
}

class ResFrame extends Frame {
  const ResFrame({required this.id, required this.ok, this.payload, this.error});
  final String id;
  final bool ok;
  /// Gateway uses "payload" (not "result") for success responses.
  final Map<String, dynamic>? payload;
  final ResError? error;
}

class ResError {
  const ResError({required this.code, required this.message, this.details});
  final String code;
  final String message;
  final Map<String, dynamic>? details;
}

class EventFrame extends Frame {
  const EventFrame({required this.event, required this.payload, this.seq});
  final String event;
  final Map<String, dynamic> payload;
  final int? seq;
}

Frame decodeFrame(String raw) {
  final m = jsonDecode(raw) as Map<String, dynamic>;
  switch (m['type']) {
    case 'req':
      return ReqFrame(
        id: m['id'] as String,
        method: m['method'] as String,
        params: (m['params'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
    case 'res':
      final ok = m['ok'] as bool;
      return ResFrame(
        id: m['id'] as String,
        ok: ok,
        payload: ok
            ? (m['payload'] as Map?)?.cast<String, dynamic>()
            : null,
        error: !ok && m['error'] != null
            ? ResError(
                code: (m['error']['code'] ?? '') as String,
                message: (m['error']['message'] ?? '') as String,
                details: (m['error']['details'] as Map?)?.cast<String, dynamic>(),
              )
            : null,
      );
    case 'event':
      return EventFrame(
        event: m['event'] as String,
        payload: (m['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        seq: m['seq'] as int?,
      );
    default:
      throw FormatException('unknown frame type: ${m['type']}');
  }
}

String encodeReq({
  required String id,
  required String method,
  required Map<String, dynamic> params,
}) =>
    jsonEncode({'type': 'req', 'id': id, 'method': method, 'params': params});
```

- [ ] **Step 4: Run to verify pass**

Run:
```bash
flutter test test/data/gateway/shared/envelope_codec_test.dart
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/data/gateway/shared/envelope_codec.dart test/data/gateway/shared/envelope_codec_test.dart
git commit -m "feat(gateway): typed envelope codec for req/res/event frames"
```

---

## Phase 4 — WS connection layer with reconnect

### Task 11: `WsConnection` lifecycle (open/close/messages stream)

**Files:**
- Create: `lib/data/gateway/shared/ws_connection.dart`
- Create: `test/data/gateway/shared/ws_connection_test.dart`

- [ ] **Step 1: Write the failing test using a fake socket**

Create `test/data/gateway/shared/ws_connection_test.dart`:
```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/shared/ws_connection.dart';

class FakeSocket implements RawSocketLike {
  final _in = StreamController<dynamic>.broadcast();
  final outgoing = <String>[];
  bool closed = false;

  @override
  Stream<dynamic> get stream => _in.stream;
  @override
  void send(String s) => outgoing.add(s);
  @override
  Future<void> close() async { closed = true; }

  void push(String s) => _in.add(s);
}

void main() {
  test('WsConnection forwards inbound frames as parsed Frames', () async {
    final fake = FakeSocket();
    final conn = WsConnection.test(socket: fake);
    final received = <Frame>[];
    final sub = conn.frames.listen(received.add);

    fake.push('{"type":"event","event":"connect.challenge","payload":{"nonce":"N","ts":1}}');
    await Future.delayed(Duration.zero);

    expect(received.length, 1);
    expect(received.first, isA<EventFrame>());

    await sub.cancel();
    await conn.close();
    expect(fake.closed, true);
  });

  test('send writes encoded request to socket', () {
    final fake = FakeSocket();
    final conn = WsConnection.test(socket: fake);
    conn.send('{"type":"req","id":"X","method":"m","params":{}}');
    expect(fake.outgoing, ['{"type":"req","id":"X","method":"m","params":{}}']);
  });
}
```

- [ ] **Step 2: Run to confirm fail**

Run:
```bash
flutter test test/data/gateway/shared/ws_connection_test.dart
```
Expected: compile error.

- [ ] **Step 3: Implement WsConnection**

Create `lib/data/gateway/shared/ws_connection.dart`:
```dart
import 'dart:async';

import 'package:stt_tts/core/logger.dart';
import 'package:stt_tts/data/gateway/shared/envelope_codec.dart';
import 'package:web_socket_channel/io.dart';

export 'envelope_codec.dart';

/// Minimal interface so tests can swap in a fake.
abstract class RawSocketLike {
  Stream<dynamic> get stream;
  void send(String message);
  Future<void> close();
}

class _IOAdapter implements RawSocketLike {
  _IOAdapter(this._channel);
  final IOWebSocketChannel _channel;

  @override
  Stream get stream => _channel.stream;
  @override
  void send(String message) => _channel.sink.add(message);
  @override
  Future<void> close() => _channel.sink.close();
}

class WsConnection {
  WsConnection.test({required RawSocketLike socket, Logger? log})
      : _socket = socket,
        _log = log ?? Logger(tag: 'ws') {
    _wire();
  }

  factory WsConnection.connect(Uri uri, {Logger? log}) {
    final ch = IOWebSocketChannel.connect(uri);
    return WsConnection.test(socket: _IOAdapter(ch), log: log);
  }

  final RawSocketLike _socket;
  final Logger _log;
  final _frames = StreamController<Frame>.broadcast();
  late final StreamSubscription _sub;

  void _wire() {
    _sub = _socket.stream.listen(
      (raw) {
        if (raw is! String) {
          _log.warn('non-string frame ignored');
          return;
        }
        try {
          _frames.add(decodeFrame(raw));
        } catch (e) {
          _log.error('decode error: $e');
        }
      },
      onError: (e) => _log.error('socket error: $e'),
      onDone: () => _frames.close(),
    );
  }

  Stream<Frame> get frames => _frames.stream;

  void send(String raw) => _socket.send(raw);

  Future<void> close() async {
    await _sub.cancel();
    await _frames.close();
    await _socket.close();
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run:
```bash
flutter test test/data/gateway/shared/ws_connection_test.dart
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/data/gateway/shared/ws_connection.dart test/data/gateway/shared/ws_connection_test.dart
git commit -m "feat(gateway): WsConnection with typed frame stream + fake socket for tests"
```

---

### Task 12: Request/response correlator on top of `WsConnection`

**Files:**
- Modify: `lib/data/gateway/shared/ws_connection.dart` (add `RpcChannel`)
- Modify: `test/data/gateway/shared/ws_connection_test.dart`

- [ ] **Step 1: Append the failing test for `RpcChannel`**

Append to `test/data/gateway/shared/ws_connection_test.dart` inside `void main() {…}`:
```dart
  test('RpcChannel resolves matching res frames', () async {
    final fake = FakeSocket();
    final conn = WsConnection.test(socket: fake);
    final rpc = RpcChannel(conn, idGen: () => 'ID-1');

    // Fire the request; resolve in a microtask.
    final future = rpc.request(method: 'health', params: {});
    // The send should have happened synchronously
    expect(fake.outgoing.single, contains('"id":"ID-1"'));
    // Push the matching response.
    fake.push('{"type":"res","id":"ID-1","ok":true,"result":{"ok":true}}');

    final result = await future;
    expect(result, {'ok': true});
  });

  test('RpcChannel rejects on error response', () async {
    final fake = FakeSocket();
    final conn = WsConnection.test(socket: fake);
    final rpc = RpcChannel(conn, idGen: () => 'ID-2');
    final future = rpc.request(method: 'x', params: {});
    fake.push('{"type":"res","id":"ID-2","ok":false,"error":{"code":"E","message":"M"}}');
    await expectLater(future, throwsA(isA<RpcError>()));
  });
```

- [ ] **Step 2: Run to confirm fail**

Run:
```bash
flutter test test/data/gateway/shared/ws_connection_test.dart
```
Expected: compile error / unknown class `RpcChannel`.

- [ ] **Step 3: Append `RpcChannel` to `lib/data/gateway/shared/ws_connection.dart`**

Add at the bottom of `ws_connection.dart`:
```dart
class RpcError implements Exception {
  RpcError(this.code, this.message, {this.details});
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  @override
  String toString() => 'RpcError($code): $message';
}

class RpcChannel {
  RpcChannel(this._conn, {String Function()? idGen})
      : _idGen = idGen ?? (() => DateTime.now().microsecondsSinceEpoch.toString()) {
    _sub = _conn.frames.listen(_onFrame);
  }

  final WsConnection _conn;
  final String Function() _idGen;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  late final StreamSubscription _sub;

  /// Stream of server-pushed events (no res correlation).
  Stream<EventFrame> get events => _conn.frames.where((f) => f is EventFrame).cast<EventFrame>();

  Future<Map<String, dynamic>> request({
    required String method,
    required Map<String, dynamic> params,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final id = _idGen();
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _conn.send(
      // Inline encode to avoid an import cycle; envelope_codec.dart's encodeReq is OK to use too.
      '{"type":"req","id":"$id","method":"$method","params":${_encodeJson(params)}}',
    );
    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw RpcError('TIMEOUT', 'request $method timed out');
    });
  }

  void send({required String method, required Map<String, dynamic> params}) {
    final id = _idGen();
    _conn.send(
      '{"type":"req","id":"$id","method":"$method","params":${_encodeJson(params)}}',
    );
  }

  void _onFrame(Frame f) {
    if (f is! ResFrame) return;
    final completer = _pending.remove(f.id);
    if (completer == null) return;
    if (f.ok) {
      completer.complete(f.payload ?? const {});
    } else {
      final e = f.error!;
      completer.completeError(RpcError(e.code, e.message, details: e.details));
    }
  }

  Future<void> close() async {
    await _sub.cancel();
    for (final c in _pending.values) {
      c.completeError(RpcError('CANCELLED', 'channel closed'));
    }
    _pending.clear();
  }

  static String _encodeJson(Object? o) {
    // Reuse dart:convert via the codec module is ideal, but inlining keeps this file self-contained.
    return _toJson(o);
  }
}

// Inline JSON encoder to avoid duplicating envelope_codec imports here. We can replace with jsonEncode if preferred.
String _toJson(Object? o) {
  if (o == null) return 'null';
  if (o is String) return '"${o.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  if (o is num || o is bool) return o.toString();
  if (o is List) return '[${o.map(_toJson).join(',')}]';
  if (o is Map) {
    final entries = o.entries.map((e) => '"${e.key}":${_toJson(e.value)}');
    return '{${entries.join(',')}}';
  }
  throw ArgumentError('cannot encode $o');
}
```

> NOTE: Replace the inline `_toJson` with `jsonEncode` from `dart:convert` once you're sure params don't carry any non-JSON-friendly values. Both work; `jsonEncode` is friendlier for nested structures.

- [ ] **Step 4: Run to verify pass**

Run:
```bash
flutter test test/data/gateway/shared/ws_connection_test.dart
```
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/data/gateway/shared/ws_connection.dart test/data/gateway/shared/ws_connection_test.dart
git commit -m "feat(gateway): add RpcChannel for req/res correlation"
```

---

### Task 13: Reconnect / backoff wrapper

**Files:**
- Create: `lib/data/gateway/shared/reconnect_loop.dart`
- Create: `test/data/gateway/shared/reconnect_loop_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/gateway/shared/reconnect_loop_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/shared/reconnect_loop.dart';

void main() {
  test('backoff sequence is 1,2,4,8,16,30,30,...', () {
    final r = ReconnectLoop();
    expect(r.nextBackoffMs(), 1000);
    expect(r.nextBackoffMs(), 2000);
    expect(r.nextBackoffMs(), 4000);
    expect(r.nextBackoffMs(), 8000);
    expect(r.nextBackoffMs(), 16000);
    expect(r.nextBackoffMs(), 30000);
    expect(r.nextBackoffMs(), 30000);
  });

  test('reset goes back to 800ms (matches gateway default)', () {
    final r = ReconnectLoop();
    r.nextBackoffMs();
    r.nextBackoffMs();
    r.reset();
    expect(r.nextBackoffMs(), 800);
  });
}
```

- [ ] **Step 2: Run to confirm fail**

Run:
```bash
flutter test test/data/gateway/shared/reconnect_loop_test.dart
```
Expected: compile error.

- [ ] **Step 3: Implement**

Create `lib/data/gateway/shared/reconnect_loop.dart`:
```dart
class ReconnectLoop {
  static const _cap = 30000;
  int _next = 1000;
  bool _afterReset = false;

  int nextBackoffMs() {
    if (_afterReset) {
      _afterReset = false;
      _next = 1600; // next-after-reset becomes 800 → 1600 → 3200 …
      return 800;
    }
    final v = _next > _cap ? _cap : _next;
    _next = (_next * 2).clamp(0, _cap);
    return v;
  }

  void reset() {
    _next = 1000;
    _afterReset = true;
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run:
```bash
flutter test test/data/gateway/shared/reconnect_loop_test.dart
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/data/gateway/shared/reconnect_loop.dart test/data/gateway/shared/reconnect_loop_test.dart
git commit -m "feat(gateway): exponential backoff loop with 800ms reset"
```

---

## Phase 5 — OpenClaw connect plan

### Task 14: Canonical-string builder (`canonical.dart`)

**Files:**
- Create: `lib/data/gateway/agents/openclaw/canonical.dart`
- Create: `test/data/gateway/agents/openclaw/canonical_test.dart`

The canonical format was extracted from the SPA bundle's `nt()` function and is documented in `2026-04-29-openclaw-mobile-protocol-capture.md` §3.4. **Pipe-delimited, prefixed with `v2|`.**

- [ ] **Step 1: Write the failing test (golden-text against the captured request)**

Create `test/data/gateway/agents/openclaw/canonical_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/canonical.dart';

void main() {
  test('canonical matches the captured `connect` request exactly', () {
    final s = buildCanonical(
      deviceId: '759fe82249316fdc36e3f306ebacfe54b2e33e4a2a73772911c33c570cbc9934',
      clientId: 'openclaw-control-ui',
      clientMode: 'webchat',
      role: 'operator',
      scopes: const [
        'operator.admin','operator.read','operator.write',
        'operator.approvals','operator.pairing',
      ],
      signedAtMs: 1777443641132,
      token: 'test-123',
      nonce: '4aafea19-095b-40e6-bd18-7d0739ee6c34',
    );
    expect(s,
      'v2|759fe82249316fdc36e3f306ebacfe54b2e33e4a2a73772911c33c570cbc9934'
      '|openclaw-control-ui|webchat|operator'
      '|operator.admin,operator.read,operator.write,operator.approvals,operator.pairing'
      '|1777443641132|test-123|4aafea19-095b-40e6-bd18-7d0739ee6c34');
  });

  test('null token becomes empty segment', () {
    final s = buildCanonical(
      deviceId: 'D', clientId: 'C', clientMode: 'webchat', role: 'operator',
      scopes: const ['a'], signedAtMs: 1, token: null, nonce: 'N',
    );
    expect(s, 'v2|D|C|webchat|operator|a|1||N');
  });
}
```

- [ ] **Step 2: Run to confirm fail**

```bash
flutter test test/data/gateway/agents/openclaw/canonical_test.dart
```

- [ ] **Step 3: Implement (verbatim from `nt()`)**

Create `lib/data/gateway/agents/openclaw/canonical.dart`:
```dart
/// Builds the canonical signing string per the gateway's `nt()`.
/// Format: `v2|deviceId|clientId|clientMode|role|scopes,joined|signedAtMs|token|nonce`
/// (token segment is empty when null/missing).
String buildCanonical({
  required String deviceId,
  required String clientId,
  required String clientMode,
  required String role,
  required List<String> scopes,
  required int signedAtMs,
  required String? token,
  required String nonce,
}) {
  final scopesJoined = scopes.join(',');
  final tokenStr = token ?? '';
  return 'v2|$deviceId|$clientId|$clientMode|$role|$scopesJoined|$signedAtMs|$tokenStr|$nonce';
}
```

- [ ] **Step 4: Run to verify pass**

Run:
```bash
flutter test test/data/gateway/agents/openclaw/canonical_test.dart
```
Expected: pass (assuming the placeholder matches your documented format; if not, fix the format in the file until it does).

- [ ] **Step 5: Commit**

```bash
git add lib/data/gateway/agents/openclaw/canonical.dart test/data/gateway/agents/openclaw/canonical_test.dart
git commit -m "feat(openclaw): canonical-string builder for device-proof signing"
```

---

### Task 15: `DeviceProof` builder (signs canonical, returns SPKI + base64 signature)

**Files:**
- Create: `lib/data/gateway/agents/openclaw/device_proof.dart`
- Create: `test/data/gateway/agents/openclaw/device_proof_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/gateway/agents/openclaw/device_proof_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/device_proof.dart';
import 'package:stt_tts/data/gateway/shared/device_identity.dart';
import 'package:stt_tts/data/secure/secure_store.dart';

void main() {
  test('build returns the gateway-required device shape', () async {
    final id = await DeviceIdentityManager(store: FakeSecureStore()).loadOrCreate();
    final proof = await buildDeviceProof(
      identity: id,
      clientId: 'openclaw-android',
      clientMode: 'webchat',
      role: 'operator',
      scopes: const ['operator.admin'],
      token: 'test-123',
      nonce: 'NONCE',
      now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    expect(proof['id'], id.deviceId);                 // 64 hex chars
    expect(proof['publicKey'], id.publicKeyB64u);     // base64url-no-pad
    expect(proof['signature'], isA<String>());
    expect((proof['signature'] as String).length, 86); // 64 bytes b64u no pad
    expect((proof['signature'] as String).contains('='), false);
    expect(proof['signedAt'], 1700000000000);
    expect(proof['nonce'], 'NONCE');
  });
}
```

- [ ] **Step 2: Run to confirm fail**

Run:
```bash
flutter test test/data/gateway/agents/openclaw/device_proof_test.dart
```
Expected: compile error.

- [ ] **Step 3: Implement (Ed25519 sign, base64url-no-pad)**

Create `lib/data/gateway/agents/openclaw/device_proof.dart`:
```dart
import 'package:stt_tts/data/gateway/agents/openclaw/canonical.dart';
import 'package:stt_tts/data/gateway/shared/device_identity.dart';

/// Builds the `device` block sent inside the `connect` RPC params.
/// Returns the exact JSON shape the gateway expects.
Future<Map<String, dynamic>> buildDeviceProof({
  required DeviceIdentity identity,
  required String clientId,
  required String clientMode,
  required String role,
  required List<String> scopes,
  required String? token,
  required String nonce,
  DateTime? now,
}) async {
  final signedAtMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final canonical = buildCanonical(
    deviceId: identity.deviceId,
    clientId: clientId,
    clientMode: clientMode,
    role: role,
    scopes: scopes,
    signedAtMs: signedAtMs,
    token: token,
    nonce: nonce,
  );
  final signatureB64u = await identity.signCanonical(canonical);
  return {
    'id': identity.deviceId,            // 64-char hex (sha256(pub))
    'publicKey': identity.publicKeyB64u, // base64url-no-pad of 32 raw bytes
    'signature': signatureB64u,          // base64url-no-pad of 64 raw bytes
    'signedAt': signedAtMs,
    'nonce': nonce,
  };
}
```

- [ ] **Step 4: Run to verify pass**

Run:
```bash
flutter test test/data/gateway/agents/openclaw/device_proof_test.dart
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/data/gateway/agents/openclaw/device_proof.dart test/data/gateway/agents/openclaw/device_proof_test.dart
git commit -m "feat(openclaw): build signed device proof for connect"
```

---

### Task 16: `ConnectParams` builder

**Files:**
- Create: `lib/data/gateway/agents/openclaw/connect_params.dart`

- [ ] **Step 1: Implement (no separate test — covered by integration test in Task 19)**

Create `lib/data/gateway/agents/openclaw/connect_params.dart`:
```dart
import 'dart:io';

const openClawClientId = 'openclaw-android';
const openClawClientIdIos = 'openclaw-ios';
const openClawScopes = <String>[
  'operator.admin',
  'operator.read',
  'operator.write',
  'operator.approvals',
  'operator.pairing',
];

String currentClientId() {
  if (Platform.isIOS) return openClawClientIdIos;
  return openClawClientId;
}

Map<String, dynamic> buildConnectParams({
  required String instanceId,
  required String appVersion,
  required Map<String, dynamic> deviceProof,
  required String? token,
  required String? deviceToken,
  required String userAgent,
  required String locale,
}) {
  final auth = <String, dynamic>{};
  if (token != null) auth['token'] = token;
  if (deviceToken != null) auth['deviceToken'] = deviceToken;

  return {
    'minProtocol': 3,
    'maxProtocol': 3,
    'client': {
      'id': currentClientId(),
      'version': appVersion,
      'platform': Platform.operatingSystem,
      'mode': 'webchat',
      'instanceId': instanceId,
    },
    'role': 'operator',
    'scopes': openClawScopes,
    'device': deviceProof,
    'caps': const ['tool-events'],
    'auth': auth,
    'userAgent': userAgent,
    'locale': locale,
  };
}
```

- [ ] **Step 2: Quick analyze**

Run:
```bash
flutter analyze lib/data/gateway/agents/openclaw/connect_params.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/data/gateway/agents/openclaw/connect_params.dart
git commit -m "feat(openclaw): build connect RPC params"
```

---

## Phase 6 — `GatewayClient` interface + OpenClaw impl

### Task 17: Define interface + supporting types

**Files:**
- Create: `lib/data/gateway/gateway_client.dart`
- Create: `lib/data/gateway/connection_config.dart`

- [ ] **Step 1: Write the interface (no test — abstract types)**

Create `lib/data/gateway/connection_config.dart`:
```dart
class ConnectionConfig {
  const ConnectionConfig({required this.wsUrl, this.token, this.deviceToken});
  final String wsUrl;            // e.g. ws://192.168.1.10:18789/
  final String? token;           // shared gateway token (used at first pair only)
  final String? deviceToken;     // long-lived per-device token (preferred when present)
}
```

Create `lib/data/gateway/gateway_client.dart`:
```dart
import 'dart:async';

import 'package:stt_tts/data/gateway/connection_config.dart';

enum ConnectionState { idle, connecting, authenticated, disconnected, failed }

class HelloResult {
  const HelloResult({required this.deviceToken, required this.role, required this.scopes});
  final String? deviceToken;
  final String role;
  final List<String> scopes;
}

class GatewayCapabilities {
  const GatewayCapabilities({
    required this.streaming,
    required this.sources,
    required this.plugins,
  });
  final bool streaming;
  final bool sources;
  final bool plugins;
}

abstract class GatewayClient {
  /// Open the socket, authenticate, return Hello on success.
  Future<HelloResult> connect(ConnectionConfig config);

  /// Tear down. Idempotent.
  Future<void> disconnect();

  /// State stream for the UI.
  Stream<ConnectionState> get connectionState;

  GatewayCapabilities get capabilities;
}
```

- [ ] **Step 2: Verify analyze**

Run:
```bash
flutter analyze lib/data/gateway/
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/data/gateway/gateway_client.dart lib/data/gateway/connection_config.dart
git commit -m "feat(gateway): define agent-agnostic GatewayClient interface"
```

---

### Task 18: `OpenClawGatewayClient` — connect implementation

**Files:**
- Create: `lib/data/gateway/agents/openclaw/openclaw_client.dart`

- [ ] **Step 1: Implement (integration-tested in Task 19)**

Create `lib/data/gateway/agents/openclaw/openclaw_client.dart`:
```dart
import 'dart:async';

import 'package:stt_tts/core/ids.dart';
import 'package:stt_tts/core/logger.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/connect_params.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/device_proof.dart';
import 'package:stt_tts/data/gateway/connection_config.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/data/gateway/shared/device_identity.dart';
import 'package:stt_tts/data/gateway/shared/envelope_codec.dart';
import 'package:stt_tts/data/gateway/shared/ws_connection.dart';

class OpenClawGatewayClient implements GatewayClient {
  OpenClawGatewayClient({
    required DeviceIdentityManager identityManager,
    String appVersion = '0.1.0',
    String userAgent = 'OpenClaw-Mobile/0.1.0',
    String locale = 'en-US',
    Logger? log,
  })  : _identityManager = identityManager,
        _appVersion = appVersion,
        _userAgent = userAgent,
        _locale = locale,
        _log = log ?? Logger(tag: 'openclaw');

  final DeviceIdentityManager _identityManager;
  final String _appVersion;
  final String _userAgent;
  final String _locale;
  final Logger _log;

  final _state = StreamController<ConnectionState>.broadcast();
  WsConnection? _conn;
  RpcChannel? _rpc;
  StreamSubscription? _challengeSub;

  String? _instanceId;

  @override
  Stream<ConnectionState> get connectionState => _state.stream;

  @override
  GatewayCapabilities get capabilities =>
      const GatewayCapabilities(streaming: true, sources: true, plugins: true);

  @override
  Future<HelloResult> connect(ConnectionConfig config) async {
    _state.add(ConnectionState.connecting);

    final identity = await _identityManager.loadOrCreate();
    _instanceId ??= newInstanceId();

    final conn = WsConnection.connect(Uri.parse(config.wsUrl), log: _log);
    _conn = conn;
    final rpc = RpcChannel(conn, idGen: newRequestId);
    _rpc = rpc;

    // Wait for connect.challenge
    final challenge = await conn.frames
        .where((f) => f is EventFrame && f.event == 'connect.challenge')
        .cast<EventFrame>()
        .first
        .timeout(const Duration(seconds: 10));

    final nonce = challenge.payload['nonce'] as String;
    _log.info('challenge received, nonce=$nonce');

    // Build the device proof
    final proof = await buildDeviceProof(
      identity: identity,
      clientId: currentClientId(),
      clientMode: 'webchat',
      role: 'operator',
      scopes: openClawScopes,
      token: config.deviceToken == null ? config.token : null,
      nonce: nonce,
    );

    final params = buildConnectParams(
      instanceId: _instanceId!,
      appVersion: _appVersion,
      deviceProof: proof,
      token: config.deviceToken == null ? config.token : null,
      deviceToken: config.deviceToken,
      userAgent: _userAgent,
      locale: _locale,
    );

    // The gateway wraps the Hello inside `payload` (RpcChannel.request returns
    // the unwrapped payload map for ok responses), and the Hello has its own
    // nested `auth` block.
    final hello = await rpc.request(method: 'connect', params: params);
    final auth = (hello['auth'] as Map?)?.cast<String, dynamic>();
    final result = HelloResult(
      deviceToken: auth?['deviceToken'] as String?,
      role: auth?['role'] as String? ?? 'operator',
      scopes: ((auth?['scopes'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
    );

    _state.add(ConnectionState.authenticated);
    _log.info('authenticated. deviceToken received: ${result.deviceToken != null}');
    return result;
  }

  @override
  Future<void> disconnect() async {
    _state.add(ConnectionState.disconnected);
    await _challengeSub?.cancel();
    await _rpc?.close();
    await _conn?.close();
    _challengeSub = null;
    _rpc = null;
    _conn = null;
  }
}
```

- [ ] **Step 2: Analyze**

Run:
```bash
flutter analyze lib/data/gateway/
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/data/gateway/agents/openclaw/openclaw_client.dart
git commit -m "feat(openclaw): GatewayClient impl — connect handshake end-to-end"
```

---

### Task 19: Integration test — real connect against running gateway

**Files:**
- Create: `test/data/gateway/agents/openclaw/openclaw_client_integration_test.dart`

- [ ] **Step 1: Write the test (skipped if `OPENCLAW_INTEGRATION` env var unset)**

Create `test/data/gateway/agents/openclaw/openclaw_client_integration_test.dart`:
```dart
@Tags(['integration'])

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/openclaw_client.dart';
import 'package:stt_tts/data/gateway/connection_config.dart';
import 'package:stt_tts/data/gateway/shared/device_identity.dart';
import 'package:stt_tts/data/secure/secure_store.dart';

void main() {
  final integration = Platform.environment['OPENCLAW_INTEGRATION'] == '1';
  final url = Platform.environment['OPENCLAW_URL'] ?? 'ws://127.0.0.1:18789/';
  final token = Platform.environment['OPENCLAW_TOKEN'] ?? 'test-123';

  test(
    'connect to a running gateway, receive Hello with deviceToken',
    () async {
      final client = OpenClawGatewayClient(
        identityManager: DeviceIdentityManager(store: FakeSecureStore()),
      );
      final hello = await client.connect(
        ConnectionConfig(wsUrl: url, token: token),
      );
      expect(hello.role, isNotEmpty);
      // deviceToken may or may not be returned depending on gateway version
      await client.disconnect();
    },
    skip: integration ? null : 'set OPENCLAW_INTEGRATION=1 with a running gateway',
    tags: ['integration'],
  );
}
```

- [ ] **Step 2: Run with the gateway up**

Run:
```bash
OPENCLAW_INTEGRATION=1 flutter test --tags integration test/data/gateway/agents/openclaw/openclaw_client_integration_test.dart
```
Expected: pass. If it fails with `INVALID_REQUEST` mentioning a `params` field, the canonical-string format from Task 14 doesn't match the gateway's `nt()` — re-verify against the protocol-capture doc.

- [ ] **Step 3: Commit**

```bash
git add test/data/gateway/agents/openclaw/openclaw_client_integration_test.dart
git commit -m "test(openclaw): integration test — real connect handshake"
```

---

## Phase 7 — Riverpod state

### Task 20: `connectionProvider` + `gatewayClientProvider`

**Files:**
- Create: `lib/state/connection_provider.dart`

- [ ] **Step 1: Write providers (no separate unit test — covered by widget tests in Phase 8)**

Create `lib/state/connection_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/openclaw_client.dart';
import 'package:stt_tts/data/gateway/connection_config.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/data/gateway/shared/device_identity.dart';
import 'package:stt_tts/data/secure/secure_store.dart';

final secureStoreProvider = Provider<SecureStore>((_) => FlutterSecureStore());
final deviceIdentityManagerProvider = Provider<DeviceIdentityManager>(
  (ref) => DeviceIdentityManager(store: ref.read(secureStoreProvider)),
);
final gatewayClientProvider = Provider<GatewayClient>(
  (ref) => OpenClawGatewayClient(
    identityManager: ref.read(deviceIdentityManagerProvider),
  ),
);

final connectionStateProvider = StreamProvider<ConnectionState>((ref) {
  return ref.watch(gatewayClientProvider).connectionState;
});

class PairController extends StateNotifier<AsyncValue<HelloResult?>> {
  PairController(this._ref) : super(const AsyncValue.data(null));
  final Ref _ref;

  Future<void> pair({required String wsUrl, required String token}) async {
    state = const AsyncValue.loading();
    final client = _ref.read(gatewayClientProvider);
    final config = ConnectionConfig(wsUrl: wsUrl, token: token);
    try {
      final hello = await client.connect(config);
      // Persist deviceToken for next launch
      if (hello.deviceToken != null) {
        await _ref
            .read(secureStoreProvider)
            .write('oc.deviceToken', hello.deviceToken!);
        await _ref.read(secureStoreProvider).write('oc.wsUrl', wsUrl);
      }
      state = AsyncValue.data(hello);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final pairControllerProvider =
    StateNotifierProvider<PairController, AsyncValue<HelloResult?>>(
  (ref) => PairController(ref),
);
```

- [ ] **Step 2: Analyze**

Run:
```bash
flutter analyze lib/state/
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/state/connection_provider.dart
git commit -m "feat(state): connection + pair Riverpod providers"
```

---

## Phase 8 — Manual pair UI

### Task 21: Themed widgets — `OcButton`, `OcTextField`

**Files:**
- Create: `lib/ui/widgets/oc_button.dart`
- Create: `lib/ui/widgets/oc_text_field.dart`

- [ ] **Step 1: Implement OcButton**

Create `lib/ui/widgets/oc_button.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

enum OcButtonStyle { primary, secondary }

class OcButton extends StatelessWidget {
  const OcButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = OcButtonStyle.primary,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final OcButtonStyle style;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isPrimary = style == OcButtonStyle.primary;
    return GestureDetector(
      onTap: busy ? null : onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isPrimary ? OcColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: isPrimary
              ? null
              : Border.all(color: OcColors.borderTint),
          boxShadow: isPrimary && !busy
              ? const [
                  BoxShadow(
                    color: Color(0x596CB0FF),
                    blurRadius: 22,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: busy
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: OcColors.bgBottom),
              )
            : Text(
                label,
                style: TextStyle(
                  color: isPrimary ? OcColors.bgBottom : OcColors.textSubtitle,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }
}
```

- [ ] **Step 2: Implement OcTextField**

Create `lib/ui/widgets/oc_text_field.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

class OcTextField extends StatelessWidget {
  const OcTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.keyboardType,
  });

  final String label;
  final String? hint;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: OcColors.textSubtitle,
            fontWeight: FontWeight.w600,
            fontSize: 11,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          style: const TextStyle(color: OcColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: OcColors.textMeta),
            filled: true,
            fillColor: OcColors.overlayTint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: OcColors.borderTint),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: OcColors.borderTint),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: OcColors.accent),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Analyze**

Run:
```bash
flutter analyze lib/ui/widgets/
```
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/widgets/oc_button.dart lib/ui/widgets/oc_text_field.dart
git commit -m "feat(ui): themed OcButton and OcTextField widgets"
```

---

### Task 22: Welcome screen

**Files:**
- Modify: `lib/ui/onboarding/welcome_screen.dart` (replace stub)

- [ ] **Step 1: Implement**

Replace `lib/ui/onboarding/welcome_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/ui/onboarding/pair_form_screen.dart';
import 'package:stt_tts/ui/widgets/oc_button.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: ocBackgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      colors: [OcColors.accent, OcColors.accent2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x736CB0FF),
                        blurRadius: 26,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      '⌘',
                      style: TextStyle(fontSize: 38, color: OcColors.bgBottom, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'OpenClaw',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: OcColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Connect to your OpenClaw to start.',
                  style: TextStyle(color: OcColors.textSubtitle, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const Spacer(flex: 3),
                OcButton(
                  label: 'Connect to my OpenClaw',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PairFormScreen()),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it builds**

Run:
```bash
flutter analyze lib/
```
Expected: no errors. (`PairFormScreen` is referenced but not yet created — temporarily comment the navigation if you're committing this task before Task 23.)

- [ ] **Step 3: Commit**

```bash
git add lib/ui/onboarding/welcome_screen.dart
git commit -m "feat(ui): welcome screen"
```

---

### Task 23: Pair-form screen + connecting + ready

**Files:**
- Create: `lib/ui/onboarding/pair_form_screen.dart`
- Create: `lib/ui/onboarding/connecting_screen.dart`
- Create: `lib/ui/onboarding/ready_screen.dart`

- [ ] **Step 1: Implement pair form**

Create `lib/ui/onboarding/pair_form_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/connection_provider.dart';
import 'package:stt_tts/ui/onboarding/connecting_screen.dart';
import 'package:stt_tts/ui/widgets/oc_button.dart';
import 'package:stt_tts/ui/widgets/oc_text_field.dart';

class PairFormScreen extends ConsumerStatefulWidget {
  const PairFormScreen({super.key});
  @override
  ConsumerState<PairFormScreen> createState() => _PairFormScreenState();
}

class _PairFormScreenState extends ConsumerState<PairFormScreen> {
  final _url = TextEditingController(text: 'ws://127.0.0.1:18789/');
  final _token = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: OcColors.textPrimary,
        title: const Text('Connect'),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: ocBackgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                const Text(
                  'Pair this phone to your gateway',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: OcColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "URL and gateway token from your .env. The token is only kept until pairing succeeds.",
                  style: TextStyle(color: OcColors.textSubtitle, fontSize: 12),
                ),
                const SizedBox(height: 22),
                OcTextField(
                  label: 'Gateway URL',
                  controller: _url,
                  hint: 'ws://192.168.1.10:18789',
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 14),
                OcTextField(
                  label: 'Gateway token',
                  controller: _token,
                  hint: 'OPENCLAW_GATEWAY_TOKEN',
                  obscure: true,
                ),
                const Spacer(),
                OcButton(
                  label: 'Connect',
                  onPressed: () {
                    final url = _url.text.trim();
                    final token = _token.text.trim();
                    if (url.isEmpty || token.isEmpty) return;
                    ref.read(pairControllerProvider.notifier).pair(wsUrl: url, token: token);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ConnectingScreen()),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Implement connecting screen (watches the controller)**

Create `lib/ui/onboarding/connecting_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/connection_provider.dart';
import 'package:stt_tts/ui/onboarding/ready_screen.dart';
import 'package:stt_tts/ui/widgets/oc_button.dart';

class ConnectingScreen extends ConsumerWidget {
  const ConnectingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(pairControllerProvider, (prev, next) {
      next.whenOrNull(
        data: (hello) {
          if (hello != null) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const ReadyScreen()),
              (_) => false,
            );
          }
        },
      );
    });
    final state = ref.watch(pairControllerProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: ocBackgroundGradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: state.when(
                loading: () => const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 80,
                      width: 80,
                      child: CircularProgressIndicator(color: OcColors.accent),
                    ),
                    SizedBox(height: 22),
                    Text(
                      'Pairing this device…',
                      style: TextStyle(
                        color: OcColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                data: (_) => const SizedBox(),
                error: (e, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: OcColors.danger, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      "Couldn't pair",
                      style: TextStyle(
                        color: OcColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      e.toString(),
                      style: const TextStyle(color: OcColors.textSubtitle, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    OcButton(
                      label: 'Try again',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Implement ready screen (slice 1A endpoint)**

Create `lib/ui/onboarding/ready_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/ui/widgets/oc_button.dart';

class ReadyScreen extends StatelessWidget {
  const ReadyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: ocBackgroundGradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: OcColors.overlayTint,
                      border: Border.all(color: OcColors.accent, width: 2),
                    ),
                    child: const Center(
                      child: Icon(Icons.check, color: OcColors.accent, size: 36),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    "You're in",
                    style: TextStyle(
                      color: OcColors.textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Connection live. Slice 1B will land the chat UI here.',
                    style: TextStyle(color: OcColors.textSubtitle, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 26),
                  OcButton(label: 'Done for now', onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Verify it builds**

Run:
```bash
flutter analyze
```
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/onboarding/pair_form_screen.dart lib/ui/onboarding/connecting_screen.dart lib/ui/onboarding/ready_screen.dart
git commit -m "feat(ui): pair form + connecting + ready screens"
```

---

## Phase 9 — Smoke test on a real device + cleanup

### Task 24: Run on device against your local OpenClaw

**Files:**
- None — manual smoke test.

- [ ] **Step 1: Confirm gateway is up**

Run:
```bash
docker ps --format '{{.Names}}\t{{.Status}}'
curl -I http://127.0.0.1:18789/
```
Expected: openclaw container `Up`, HTTP 200 from the dashboard.

- [ ] **Step 2: Run app on device**

Connect a phone via USB or start an emulator. Run:
```bash
flutter run
```

- [ ] **Step 3: Walk through the flow**

In the app:
1. Tap **Connect to my OpenClaw**
2. Leave URL as `ws://<your-laptop-ip>:18789/` — replace `127.0.0.1` with your machine's LAN IP if you're testing on a real phone
3. Paste your `OPENCLAW_GATEWAY_TOKEN` (`test-123` for the dev container)
4. Tap **Connect**
5. Confirm the spinner shows for 1–2s, then "You're in"

- [ ] **Step 4: Confirm `deviceToken` was persisted**

Run on the running emulator (or via `adb shell`):
```bash
adb shell run-as com.example.stt_tts ls /data/data/com.example.stt_tts/shared_prefs/
```
The encrypted-shared-prefs file should exist. (We can't read it — that's the point — but its presence confirms persistence ran.)

- [ ] **Step 5: Kill and re-launch the app, verify deviceToken auto-reuse**

Re-launch. The welcome screen still shows for now (auto-reconnect on launch is a nice-to-have for plan 1B). What we DO verify here: tapping Connect with the same URL but **leaving the token field empty** should still succeed — because the `OpenClawGatewayClient` will use the stored `deviceToken` when present.

- [ ] **Step 6: Commit any tweaks**

```bash
git add -A
git commit -m "chore: slice 1A smoke test passes against local OpenClaw"
```

---

### Task 25: Delete legacy `lib/main.dart` POC residue

**Files:**
- Modify: `lib/main.dart` (already did this in Task 7, this task verifies no orphan files remain)

- [ ] **Step 1: Verify no orphan files**

Run:
```bash
grep -rn "_SttTtsHomePageState\|class SttTtsHomePage" lib/
```
Expected: no matches (all replaced in Task 7 / restructure).

- [ ] **Step 2: Verify all tests still pass**

Run:
```bash
flutter test
flutter analyze
```
Expected: green.

- [ ] **Step 3: Commit (no-op if nothing changed)**

```bash
git status
# If anything to commit:
git add -A && git commit -m "chore: confirm POC residue removed"
```

---

## Self-review checklist

**Spec coverage** for sections relevant to slice 1A:
- §1 (goal, audience) — covered indirectly; manual pair UX is the dev-mode entrance
- §4 folder layout — implemented exactly: `core/`, `data/secure/`, `data/gateway/shared/`, `data/gateway/agents/openclaw/`, `state/`, `ui/onboarding/`, `ui/widgets/`
- §4.1 GatewayClient interface — Task 17
- §5 OpenClaw wire protocol — Tasks 10–18 (envelope, connect, device proof)
- §5.6 reconnect/heartbeat — partially covered (backoff in Task 13; heartbeat itself deferred to plan 1B since slice 1A's only need is initial connect)
- §6.1 manual pair onboarding — Tasks 22, 23
- §20 security posture — gateway token kept only until Hello, deviceToken persisted in flutter_secure_storage; matches §20

**Out of scope for 1A** (covered in 1B-1D):
- Sessions list, chat history, streaming render → 1B
- Voice services, voice state machine, karaoke → 1C
- Wake word, settings panels, error/empty states → 1D

**Placeholder scan:** the Step 3 of Task 14 has a placeholder canonical format that must be matched against Task 0.2's findings. This is the single piece of speculative content in the plan, and it's flagged inline as such.

**Type consistency:** `Result`, `RpcChannel`, `RpcError`, `Frame`, `WsConnection`, `DeviceIdentity`, `DeviceIdentityManager`, `GatewayClient`, `ConnectionConfig`, `ConnectionState`, `HelloResult`, `OpenClawGatewayClient` — all defined and used consistently across tasks.

**Reconnect-on-disconnect** is a known gap deferred to plan 1B (alongside the chat UI it enables). Slice 1A's success criterion is "first connect succeeds and deviceToken is persisted."
