---
project: OpenClaw Mobile
status: verified against running gateway 2026.4.11
date: 2026-04-29
---

# OpenClaw Gateway Protocol — Verified Capture

This document is the **source of truth** for the OpenClaw wire protocol. Every JSON shape and crypto detail below was captured from a real `connect` round-trip against `ws://127.0.0.1:18789/` (gateway image `ghcr.io/openclaw/openclaw:2026.4.11`).

## 1. Frame envelope

```jsonc
// Server → client: pushed event
{"type":"event","event":"<dotted.name>","payload":{...},"seq":<int?>}

// Client → server: request
{"type":"req","id":"<uuid>","method":"<dotted.name>","params":{...}}

// Server → client: success response (CORRECTION: field is "payload", not "result")
{"type":"res","id":"<matches request>","ok":true,"payload":{...}}

// Server → client: error response
{"type":"res","id":"<matches request>","ok":false,"error":{"code":"<CODE>","message":"...","details":{...}}}
```

## 2. Connect handshake

### 2.1 Server pushes challenge

```json
{
  "type": "event",
  "event": "connect.challenge",
  "payload": {
    "nonce": "4aafea19-095b-40e6-bd18-7d0739ee6c34",
    "ts": 1777443641130
  }
}
```

### 2.2 Client sends `connect` request

Captured verbatim from the OpenClaw Control SPA:

```json
{
  "type": "req",
  "id": "bc1a5515-4757-4c6b-a0d0-d6830854e960",
  "method": "connect",
  "params": {
    "minProtocol": 3,
    "maxProtocol": 3,
    "client": {
      "id": "openclaw-control-ui",
      "version": "2026.4.11",
      "platform": "Linux x86_64",
      "mode": "webchat",
      "instanceId": "423cb175-fbbc-41c6-a3da-5909dc3d3129"
    },
    "role": "operator",
    "scopes": [
      "operator.admin",
      "operator.read",
      "operator.write",
      "operator.approvals",
      "operator.pairing"
    ],
    "device": {
      "id": "759fe82249316fdc36e3f306ebacfe54b2e33e4a2a73772911c33c570cbc9934",
      "publicKey": "bDOXvG6txunxyeDCADzRbW7ILnQM41xk1H6PB1yElkE",
      "signature": "kbq4_NQEZbLddRRTtyC9A68keJnoPvsgLeBN4Gxu8jGuTcuSJYZHAg0-ePY7fUNTp0PxEZb2z93ugul5Gw4PCg",
      "signedAt": 1777443641132,
      "nonce": "4aafea19-095b-40e6-bd18-7d0739ee6c34"
    },
    "caps": ["tool-events"],
    "auth": {"token": "test-123"},
    "userAgent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 ...",
    "locale": "en-US"
  }
}
```

For a Flutter mobile client, `client.id` becomes `"openclaw-android"` or `"openclaw-ios"` (per platform), and `client.platform` becomes `Platform.operatingSystem`.

### 2.3 Server returns Hello

```json
{
  "type": "res",
  "id": "bc1a5515-4757-4c6b-a0d0-d6830854e960",
  "ok": true,
  "payload": {
    "type": "hello-ok",
    "protocol": 3,
    "auth": {
      "deviceToken": "LPu26lOshkc1YzQFqldTgMDIco97PxSW8GkVE-HLu-w",
      "issuedAtMs": 1777423938078,
      "role": "operator",
      "scopes": ["operator.admin","operator.approvals","operator.pairing","operator.read","operator.write"]
    },
    "canvasHostUrl": "http://127.0.0.1:18789/__openclaw__/cap/...",
    "features": {
      "events": ["connect.challenge","agent","chat","session.message","session.tool","sessions.changed", ...],
      "methods": ["health","doctor.memory.status", ...],
      "policy": {"maxPayload":26214400,"maxBufferedBytes":52428800,"tickIntervalMs":30000}
    },
    "server": {"version":"2026.4.11","connId":"a3d852f1-6c79-4e2f-a88f-de68cfaadfac"},
    "snapshot": { /* gateway state snapshot */ }
  }
}
```

The client persists `payload.auth.deviceToken` for subsequent connects (the shared gateway token is no longer needed once we have a deviceToken).

## 3. Crypto — Ed25519 (not ECDSA P-256)

### 3.1 Algorithm

- **Signing key:** Ed25519 (NaCl-style); secret key is 32 bytes random; public key is 32 bytes derived from secret.
- **Signature size:** 64 bytes raw (r || s).
- **No SPKI wrapping** — the public key is sent as 32 raw bytes encoded as base64url.

### 3.2 Encoding helpers (extracted from SPA bundle)

```dart
/// base64url with padding stripped (matches SPA's En())
String base64UrlNoPad(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

List<int> decodeBase64UrlNoPad(String s) {
  final padded = s + '=' * ((4 - s.length % 4) % 4);
  return base64Url.decode(padded);
}

/// lowercase hex (matches SPA's On())
String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
```

### 3.3 Device identity

- **Generated once per install** and persisted in `flutter_secure_storage`.
- `secretKey` (32 bytes) — kept on-device, never sent.
- `publicKey` (32 bytes) — sent in `connect` as `device.publicKey` (base64url-no-pad).
- `deviceId` — derived as `hex(SHA-256(publicKeyBytes))`, 64 hex chars.

```dart
// Pseudocode
final secret = Ed25519.randomSecretKey();          // 32 bytes
final pub    = Ed25519.publicKey(secret);          // 32 bytes
final deviceId = hex(sha256.convert(pub).bytes);   // 64 hex chars
```

### 3.4 Canonical signing string

Extracted verbatim from the SPA's `nt()` function:

```js
function nt(e){
  let t = e.scopes.join(`,`),
      n = e.token ?? ``;
  return [`v2`, e.deviceId, e.clientId, e.clientMode, e.role, t,
          String(e.signedAtMs), n, e.nonce].join(`|`);
}
```

In plain words:

```
v2|<deviceId>|<clientId>|<clientMode>|<role>|<scopes joined by comma>|<signedAtMs>|<token or empty>|<nonce>
```

Joined with the literal pipe character `|`. **No trailing newline. No surrounding whitespace.**

Example for the captured request:

```
v2|759fe82249316fdc36e3f306ebacfe54b2e33e4a2a73772911c33c570cbc9934|openclaw-control-ui|webchat|operator|operator.admin,operator.read,operator.write,operator.approvals,operator.pairing|1777443641132|test-123|4aafea19-095b-40e6-bd18-7d0739ee6c34
```

### 3.5 Signing flow

```dart
final canonical = 'v2|$deviceId|$clientId|$clientMode|$role|${scopes.join(",")}|$signedAtMs|${token ?? ""}|$nonce';
final canonicalBytes = utf8.encode(canonical);
final signature = await Ed25519.sign(secretKey, canonicalBytes); // 64 bytes
// device.publicKey  = base64UrlNoPad(publicKeyBytes)
// device.signature  = base64UrlNoPad(signatureBytes)
// device.id         = hex(SHA-256(publicKeyBytes))
```

## 4. Key gateway methods discovered (from Hello.features.methods)

A subset relevant for slice 1:

- `connect`, `health`, `status`
- `sessions.list`, `sessions.subscribe`, `sessions.delete`, `sessions.patch`
- `chat.send`, `chat.abort`, `chat.history`
- `models.list`, `tools.catalog`
- `doctor.memory.status`

The full list comes from `Hello.payload.features.methods` and is too long to inline here.

## 5. Key event names (from Hello.features.events)

- `connect.challenge`
- `agent`, `chat`, `session.message`, `session.tool`, `sessions.changed`
- (and more — the full list is in the captured Hello)

The exact streaming-event payload shape for chat (what `chat.send` triggers) is the next thing to capture in slice 1B's pre-flight.

## 6. Heartbeat

Server emits a `tick` event roughly every `policy.tickIntervalMs` (30s in observed deployment). Client should send something at least every 30s (e.g., a `health` request) to keep the connection lively. If the connection is idle longer, expect a graceful close.

## 7. Compatibility notes

- `minProtocol` and `maxProtocol` are both `3` in the captured handshake. Hard-coding `3` ties the client to gateway 2026.4.x; renegotiate when the gateway bumps protocol.
- `client.id` is enum-checked server-side — only allowlisted values are accepted (`openclaw-android`, `openclaw-ios`, `openclaw-macos`, `openclaw-control-ui`, etc.).
- `client.mode` is `webchat` in the captured handshake; flutter clients use the same value.

## 8. Corrections vs. the design spec

The spec was written against the SPA bundle's structure but had two wrong guesses now corrected by this capture:

| Item | Old (spec) | Corrected |
|---|---|---|
| Crypto | ECDSA P-256, SPKI-wrapped publicKey | **Ed25519, raw publicKey** |
| Response field | `result` | `payload` |
| `deviceId` | random UUID | **`hex(SHA-256(publicKey))`** |
| Encoding | base64 (with padding) | **base64url (no padding)** for keys/signatures; **lowercase hex** for deviceId |

Plan 1A's Tasks 9, 10, 14, 15, 18 must use the values in this document, overriding any earlier code blocks.
