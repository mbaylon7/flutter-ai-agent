# Slice 1B — Chat Mode + Sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** With slice 1A's connection layer in place, ship a working chat experience: sessions list with live updates, threaded message view, type a message → see streaming AI reply, abort mid-stream, history loads, markdown renders, sources are visible. Plus reconnect-on-disconnect and auto-reconnect on app launch using the stored `deviceToken`.

**Architecture:** A `ChatRepository` and `SessionRepository` sit on top of the slice-1A `GatewayClient` interface, exposing typed Streams the UI consumes via Riverpod. The chat UI is a `messages_provider` family keyed by `sessionId`. Streaming responses arrive as `chat.delta` (or whatever event was captured in 1A's protocol-capture doc) and rebuild only the active assistant bubble via `Riverpod.select`. Markdown via `flutter_markdown`. Sources pill opens a `showModalBottomSheet`.

**Tech Stack:** All from 1A, plus `flutter_markdown` ^0.7.5, `flutter_highlight` ^0.7.0, `intl` ^0.19.0 (for "yesterday" / "Mon" timestamps).

**Prerequisites (from slice 1A):** `OpenClawGatewayClient` connects successfully and the protocol-capture doc has the exact JSON shapes for `chat.send`, `chat.history`, streaming events, `sessions.list`, `sessions.subscribe`, `chat.abort`. **Do not start this plan until those shapes are documented.**

---

## File Structure

| Path | Responsibility |
|---|---|
| `pubspec.yaml` | Add markdown / highlight / intl deps |
| `lib/domain/models/session.dart` | `Session` data class |
| `lib/domain/models/message.dart` | `Message`, `Role`, `MessageSource`, `StreamingState`, `ContentPart`, `Source` |
| `lib/data/gateway/gateway_client.dart` | Extend with chat + session methods (was minimal in 1A) |
| `lib/data/gateway/agents/openclaw/openclaw_client.dart` | Implement those new methods + heartbeat + reconnect |
| `lib/data/gateway/agents/openclaw/event_router.dart` | Route incoming events to typed streams (chat-by-session, sessions-list) |
| `lib/data/gateway/agents/openclaw/methods.dart` | Typed wrappers for `chat.send`, `chat.history`, `sessions.list`, etc. |
| `lib/data/cache/local_store.dart` | Sqflite cache for sessions metadata + last messages tail |
| `lib/domain/repositories/session_repository.dart` | Combines gateway + cache for sessions |
| `lib/domain/repositories/chat_repository.dart` | Combines gateway for messages + streaming |
| `lib/state/sessions_provider.dart` | Sessions list + filter chips state |
| `lib/state/messages_provider.dart` | Per-session message thread state |
| `lib/state/connection_provider.dart` | Extend with auto-reconnect on launch |
| `lib/ui/shell/home_shell.dart` | Voice-first scaffold w/ swipe gestures (skeleton — voice mode lands in 1C) |
| `lib/ui/sessions/sessions_drawer.dart` | Sessions list (swipe-right) |
| `lib/ui/sessions/session_row.dart` | Single row widget |
| `lib/ui/sessions/session_search_bar.dart` | Search + filter chips |
| `lib/ui/sessions/session_actions_sheet.dart` | Long-press actions (rename / delete / pin) |
| `lib/ui/chat/chat_screen.dart` | Chat thread (swipe-up) |
| `lib/ui/chat/chat_composer.dart` | Bottom composer w/ mini mic placeholder |
| `lib/ui/chat/message_bubble.dart` | One bubble (user / assistant / tool) |
| `lib/ui/chat/markdown_renderer.dart` | `flutter_markdown` config + code-block customization |
| `lib/ui/chat/sources_pill.dart` | The "📎 N sources ▾" pill |
| `lib/ui/chat/sources_sheet.dart` | The bottom-sheet modal listing sources |
| `lib/ui/chat/working_indicator.dart` | "Looking it up…" line |
| `lib/ui/widgets/connection_banner.dart` | Top banner: offline / reconnecting / live |
| `test/domain/models/session_test.dart`, `message_test.dart` | Model invariants |
| `test/domain/repositories/chat_repository_test.dart` | Streaming aggregator tests |
| `test/data/gateway/agents/openclaw/event_router_test.dart` | Routing logic |
| `test/data/cache/local_store_test.dart` | Cache CRUD |
| `test/ui/sessions/session_row_test.dart` | Widget tests |
| `test/ui/chat/message_bubble_test.dart` | Streaming-state rendering |

---

## Phase 1 — Domain models

### Task 1: Add deps and refresh

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add to `dependencies`**

```yaml
  flutter_markdown: ^0.7.5
  flutter_highlight: ^0.7.0
  intl: ^0.19.0
  rxdart: ^0.28.0
```

- [ ] **Step 2: `flutter pub get` and analyze**

Run:
```bash
flutter pub get && flutter analyze
```

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add slice-1B deps (markdown, highlight, intl, rxdart)"
```

---

### Task 2: `Session` and `Message` models

**Files:**
- Create: `lib/domain/models/session.dart`
- Create: `lib/domain/models/message.dart`
- Create: `test/domain/models/session_test.dart`
- Create: `test/domain/models/message_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/domain/models/session_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/domain/models/session.dart';

void main() {
  test('Session.fromJson reads gateway shape', () {
    final s = Session.fromJson({
      'id': 'S1',
      'title': 'Hello',
      'updatedAt': '2026-04-29T10:00:00Z',
      'isCron': false,
    });
    expect(s.id, 'S1');
    expect(s.title, 'Hello');
    expect(s.updatedAt.toUtc().hour, 10);
    expect(s.pinned, false);
  });

  test('Session copyWith preserves unspecified fields', () {
    final s = Session(
      id: 'S1', title: 'old',
      updatedAt: DateTime(2026), pinned: false, hasVoiceMessages: false, isCron: false,
    );
    final next = s.copyWith(title: 'new');
    expect(next.title, 'new');
    expect(next.id, 'S1');
  });
}
```

Create `test/domain/models/message_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/domain/models/message.dart';

void main() {
  test('Message.fromJson maps role + streaming state', () {
    final m = Message.fromJson({
      'id': 'M1',
      'sessionId': 'S1',
      'role': 'assistant',
      'text': 'hi',
      'createdAt': '2026-04-29T10:00:00Z',
    });
    expect(m.role, Role.assistant);
    expect(m.streaming, StreamingState.none);
  });

  test('Message.appendDelta concatenates text', () {
    final m = Message(
      id: 'M1', sessionId: 'S1', role: Role.assistant, text: 'Hello, ',
      parts: const [], createdAt: DateTime(2026),
      source: MessageSource.typedChat, streaming: StreamingState.partial,
    );
    final next = m.appendDelta('world');
    expect(next.text, 'Hello, world');
    expect(next.streaming, StreamingState.partial);
  });
}
```

- [ ] **Step 2: Run to confirm fail**

```bash
flutter test test/domain/models/
```
Expected: compile errors.

- [ ] **Step 3: Implement**

Create `lib/domain/models/session.dart`:
```dart
class Session {
  const Session({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.pinned,
    required this.hasVoiceMessages,
    required this.isCron,
    this.lastPreview,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final bool pinned;
  final bool hasVoiceMessages;
  final bool isCron;
  final String? lastPreview;

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? 'Untitled',
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        pinned: false, // local-only; merged from cache
        hasVoiceMessages: (j['hasVoiceMessages'] as bool?) ?? false,
        isCron: (j['isCron'] as bool?) ?? false,
        lastPreview: j['lastPreview'] as String?,
      );

  Session copyWith({
    String? id,
    String? title,
    DateTime? updatedAt,
    bool? pinned,
    bool? hasVoiceMessages,
    bool? isCron,
    String? lastPreview,
  }) =>
      Session(
        id: id ?? this.id,
        title: title ?? this.title,
        updatedAt: updatedAt ?? this.updatedAt,
        pinned: pinned ?? this.pinned,
        hasVoiceMessages: hasVoiceMessages ?? this.hasVoiceMessages,
        isCron: isCron ?? this.isCron,
        lastPreview: lastPreview ?? this.lastPreview,
      );
}
```

Create `lib/domain/models/message.dart`:
```dart
enum Role { user, assistant, system, tool }
enum MessageSource { typedChat, spokenChat }
enum StreamingState { none, partial, finalized, failed }

class Source {
  const Source({required this.title, required this.url, this.domain});
  final String title;
  final String url;
  final String? domain;
}

class ContentPart {
  const ContentPart({required this.kind, this.text});
  final String kind; // 'text' | 'voice-directive' | …
  final String? text;
}

class Message {
  const Message({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.text,
    required this.parts,
    required this.createdAt,
    required this.source,
    required this.streaming,
    this.sources = const [],
  });

  final String id;
  final String sessionId;
  final Role role;
  final String? text;
  final List<ContentPart> parts;
  final DateTime createdAt;
  final MessageSource source;
  final StreamingState streaming;
  final List<Source> sources;

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        sessionId: j['sessionId'] as String,
        role: _parseRole(j['role'] as String?),
        text: j['text'] as String?,
        parts: const [],
        createdAt: DateTime.parse(j['createdAt'] as String),
        source: MessageSource.typedChat,
        streaming: StreamingState.none,
      );

  Message appendDelta(String chunk) => Message(
        id: id, sessionId: sessionId, role: role,
        text: (text ?? '') + chunk,
        parts: parts, createdAt: createdAt, source: source,
        streaming: streaming == StreamingState.none ? StreamingState.partial : streaming,
        sources: sources,
      );

  Message finalize({List<Source>? withSources}) => Message(
        id: id, sessionId: sessionId, role: role, text: text,
        parts: parts, createdAt: createdAt, source: source,
        streaming: StreamingState.finalized,
        sources: withSources ?? sources,
      );

  Message fail() => Message(
        id: id, sessionId: sessionId, role: role, text: text,
        parts: parts, createdAt: createdAt, source: source,
        streaming: StreamingState.failed, sources: sources,
      );

  static Role _parseRole(String? r) => switch (r) {
        'user' => Role.user,
        'assistant' => Role.assistant,
        'system' => Role.system,
        'tool' => Role.tool,
        _ => Role.assistant,
      };
}
```

- [ ] **Step 4: Run to verify pass**

```bash
flutter test test/domain/models/
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/models/ test/domain/models/
git commit -m "feat(domain): Session + Message models"
```

---

## Phase 2 — Local cache

### Task 3: `LocalStore` (sqflite cache for sessions + last messages)

**Files:**
- Create: `lib/data/cache/local_store.dart`
- Create: `test/data/cache/local_store_test.dart`

- [ ] **Step 1: Failing test (uses sqflite_common_ffi for in-memory test DB)**

Add to `pubspec.yaml` `dev_dependencies`:
```yaml
  sqflite_common_ffi: ^2.3.3
```

Create `test/data/cache/local_store_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stt_tts/data/cache/local_store.dart';
import 'package:stt_tts/domain/models/session.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('upsertSession + listSessions roundtrips', () async {
    final store = LocalStore();
    await store.openInMemory();
    await store.upsertSession(Session(
      id: 'S1', title: 'T', updatedAt: DateTime(2026),
      pinned: true, hasVoiceMessages: false, isCron: false,
    ));
    final all = await store.listSessions();
    expect(all.length, 1);
    expect(all.first.title, 'T');
    expect(all.first.pinned, true);
  });

  test('setPinned toggles pin flag', () async {
    final store = LocalStore();
    await store.openInMemory();
    await store.upsertSession(Session(
      id: 'S1', title: 'T', updatedAt: DateTime(2026),
      pinned: false, hasVoiceMessages: false, isCron: false,
    ));
    await store.setPinned('S1', true);
    final all = await store.listSessions();
    expect(all.single.pinned, true);
  });
}
```

- [ ] **Step 2: Run to confirm fail**

```bash
flutter test test/data/cache/local_store_test.dart
```
Expected: compile error.

- [ ] **Step 3: Implement**

Create `lib/data/cache/local_store.dart`:
```dart
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:stt_tts/domain/models/session.dart';

class LocalStore {
  Database? _db;

  Future<void> open() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      p.join(dir.path, 'openclaw_cache.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE sessions(
            id TEXT PRIMARY KEY,
            title TEXT,
            updatedAt TEXT,
            pinned INTEGER NOT NULL DEFAULT 0,
            hasVoice INTEGER NOT NULL DEFAULT 0,
            isCron INTEGER NOT NULL DEFAULT 0,
            preview TEXT
          )
        ''');
      },
    );
  }

  Future<void> openInMemory() async {
    _db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE sessions(
              id TEXT PRIMARY KEY,
              title TEXT,
              updatedAt TEXT,
              pinned INTEGER NOT NULL DEFAULT 0,
              hasVoice INTEGER NOT NULL DEFAULT 0,
              isCron INTEGER NOT NULL DEFAULT 0,
              preview TEXT
            )
          ''');
        },
      ),
    );
  }

  Future<void> upsertSession(Session s) async {
    await _db!.insert(
      'sessions',
      {
        'id': s.id,
        'title': s.title,
        'updatedAt': s.updatedAt.toIso8601String(),
        'pinned': s.pinned ? 1 : 0,
        'hasVoice': s.hasVoiceMessages ? 1 : 0,
        'isCron': s.isCron ? 1 : 0,
        'preview': s.lastPreview,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Session>> listSessions() async {
    final rows = await _db!.query('sessions', orderBy: 'updatedAt DESC');
    return rows
        .map((r) => Session(
              id: r['id'] as String,
              title: r['title'] as String? ?? 'Untitled',
              updatedAt: DateTime.parse(r['updatedAt'] as String),
              pinned: (r['pinned'] as int) == 1,
              hasVoiceMessages: (r['hasVoice'] as int) == 1,
              isCron: (r['isCron'] as int) == 1,
              lastPreview: r['preview'] as String?,
            ))
        .toList();
  }

  Future<void> setPinned(String id, bool pinned) async {
    await _db!.update(
      'sessions',
      {'pinned': pinned ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteSession(String id) async {
    await _db!.delete('sessions', where: 'id = ?', whereArgs: [id]);
  }
}
```

- [ ] **Step 4: Run to verify pass**

```bash
flutter test test/data/cache/local_store_test.dart
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/data/cache/local_store.dart test/data/cache/local_store_test.dart pubspec.yaml pubspec.lock
git commit -m "feat(cache): sqflite-backed LocalStore for sessions"
```

---

## Phase 3 — Extend `GatewayClient` with chat + sessions methods

### Task 4: Extend the interface

**Files:**
- Modify: `lib/data/gateway/gateway_client.dart`

- [ ] **Step 1: Add typed events + extend the interface**

Append/extend `lib/data/gateway/gateway_client.dart`:
```dart
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/domain/models/session.dart';

sealed class ChatStreamEvent {
  const ChatStreamEvent();
}

class ChatDelta extends ChatStreamEvent {
  const ChatDelta({required this.messageId, required this.text});
  final String messageId;
  final String text;
}

class ChatFinal extends ChatStreamEvent {
  const ChatFinal({required this.message});
  final Message message;
}

class ChatSourcesEvent extends ChatStreamEvent {
  const ChatSourcesEvent({required this.messageId, required this.sources});
  final String messageId;
  final List<Source> sources;
}

class ChatToolWorking extends ChatStreamEvent {
  const ChatToolWorking({required this.label});
  final String label;
}

class ChatFailed extends ChatStreamEvent {
  const ChatFailed({required this.messageId, required this.reason});
  final String messageId;
  final String reason;
}

sealed class SessionListEvent {
  const SessionListEvent();
}

class SessionAdded extends SessionListEvent {
  const SessionAdded(this.session);
  final Session session;
}

class SessionUpdated extends SessionListEvent {
  const SessionUpdated(this.session);
  final Session session;
}

class SessionRemoved extends SessionListEvent {
  const SessionRemoved(this.id);
  final String id;
}

abstract class GatewayClient {
  // ... existing connect / disconnect / connectionState / capabilities ...

  Future<List<Session>> listSessions();
  Stream<SessionListEvent> watchSessions();
  Future<void> renameSession(String id, String title);
  Future<void> deleteSession(String id);

  Future<List<Message>> loadHistory(String sessionId, {String? cursor});
  Future<void> sendMessage({
    required String sessionId,
    required String text,
    required String requestId,
  });
  Stream<ChatStreamEvent> watchChat(String sessionId);
  Future<void> abort(String requestId);
}
```

- [ ] **Step 2: Analyze (will fail because OpenClawGatewayClient no longer satisfies the interface)**

```bash
flutter analyze
```
Expected: errors about missing method overrides — that's fine, Task 5 fixes them.

- [ ] **Step 3: Commit (interface only)**

```bash
git add lib/data/gateway/gateway_client.dart
git commit -m "feat(gateway): extend interface with chat + sessions methods"
```

---

### Task 5: Event router (parses gateway events into typed streams)

**Files:**
- Create: `lib/data/gateway/agents/openclaw/event_router.dart`
- Create: `test/data/gateway/agents/openclaw/event_router_test.dart`

> Use the captured event names from `2026-04-29-openclaw-mobile-protocol-capture.md` for the actual event names. Below uses `chat.delta`, `chat.message`, `chat.sources`, `chat.failed`, `chat.toolCallsToggle` as placeholders — **replace with real names from the capture.**

- [ ] **Step 1: Failing test**

Create `test/data/gateway/agents/openclaw/event_router_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/event_router.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/data/gateway/shared/envelope_codec.dart';

void main() {
  test('routes chat.delta to ChatDelta on the matching session stream', () async {
    final router = EventRouter();
    final events = <ChatStreamEvent>[];
    router.chatStream('S1').listen(events.add);

    router.dispatch(EventFrame(
      event: 'chat.delta',
      payload: {'sessionId': 'S1', 'messageId': 'M1', 'text': 'hi'},
    ));
    await Future.delayed(Duration.zero);

    expect(events.length, 1);
    expect(events.first, isA<ChatDelta>());
    expect((events.first as ChatDelta).text, 'hi');
  });

  test('does not leak across sessions', () async {
    final router = EventRouter();
    final s1 = <ChatStreamEvent>[];
    final s2 = <ChatStreamEvent>[];
    router.chatStream('S1').listen(s1.add);
    router.chatStream('S2').listen(s2.add);
    router.dispatch(EventFrame(
      event: 'chat.delta',
      payload: {'sessionId': 'S2', 'messageId': 'M', 'text': 'x'},
    ));
    await Future.delayed(Duration.zero);
    expect(s1, isEmpty);
    expect(s2.length, 1);
  });
}
```

- [ ] **Step 2: Run to confirm fail**

```bash
flutter test test/data/gateway/agents/openclaw/event_router_test.dart
```
Expected: compile error.

- [ ] **Step 3: Implement**

Create `lib/data/gateway/agents/openclaw/event_router.dart`:
```dart
import 'dart:async';

import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/data/gateway/shared/envelope_codec.dart';
import 'package:stt_tts/domain/models/message.dart';

/// Splits a single inbound EventFrame stream into per-session ChatStreamEvent
/// streams + a sessions-list stream.
class EventRouter {
  final _chatBySession = <String, StreamController<ChatStreamEvent>>{};
  final _sessions = StreamController<SessionListEvent>.broadcast();

  Stream<ChatStreamEvent> chatStream(String sessionId) =>
      _ensure(sessionId).stream;
  Stream<SessionListEvent> sessionsStream() => _sessions.stream;

  StreamController<ChatStreamEvent> _ensure(String id) =>
      _chatBySession.putIfAbsent(
        id,
        () => StreamController<ChatStreamEvent>.broadcast(),
      );

  void dispatch(EventFrame f) {
    final p = f.payload;
    final sid = p['sessionId'] as String?;
    switch (f.event) {
      case 'chat.delta':
        if (sid == null) return;
        _ensure(sid).add(ChatDelta(
          messageId: p['messageId'] as String? ?? '',
          text: p['text'] as String? ?? '',
        ));
        break;
      case 'chat.message':
        if (sid == null) return;
        _ensure(sid).add(ChatFinal(message: Message.fromJson(p)));
        break;
      case 'chat.sources':
        if (sid == null) return;
        final list = (p['sources'] as List?) ?? const [];
        _ensure(sid).add(ChatSourcesEvent(
          messageId: p['messageId'] as String? ?? '',
          sources: list
              .cast<Map>()
              .map((m) => Source(
                    title: m['title'] as String? ?? m['url'] as String? ?? '',
                    url: m['url'] as String? ?? '',
                    domain: m['domain'] as String?,
                  ))
              .toList(),
        ));
        break;
      case 'chat.toolCallsToggle':
        if (sid == null) return;
        _ensure(sid).add(ChatToolWorking(label: p['label'] as String? ?? 'Looking it up'));
        break;
      case 'chat.failed':
        if (sid == null) return;
        _ensure(sid).add(ChatFailed(
          messageId: p['messageId'] as String? ?? '',
          reason: p['reason'] as String? ?? 'unknown',
        ));
        break;
      // Sessions
      // (Adjust event names against the captured doc.)
      case 'sessions.added':
        // Expecting payload to look like a session JSON
        // ...
        break;
    }
  }

  Future<void> close() async {
    for (final c in _chatBySession.values) {
      await c.close();
    }
    await _sessions.close();
  }
}
```

> The `sessions.*` event-name handling is intentionally left as a stub here — fill in based on the actual events you captured. Same for `chat.refreshTitle` if relevant.

- [ ] **Step 4: Run to verify pass**

```bash
flutter test test/data/gateway/agents/openclaw/event_router_test.dart
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/data/gateway/agents/openclaw/event_router.dart test/data/gateway/agents/openclaw/event_router_test.dart
git commit -m "feat(openclaw): event router for chat + sessions streams"
```

---

### Task 6: Implement chat + session methods on `OpenClawGatewayClient`

**Files:**
- Modify: `lib/data/gateway/agents/openclaw/openclaw_client.dart`

- [ ] **Step 1: Add the missing overrides**

Add to `OpenClawGatewayClient` (inside the existing class):
```dart
EventRouter? _router;

void _ensureRouter() {
  if (_router != null) return;
  _router = EventRouter();
  _conn!.frames.listen((f) {
    if (f is EventFrame) _router!.dispatch(f);
  });
}

@override
Future<List<Session>> listSessions() async {
  _ensureRouter();
  final res = await _rpc!.request(method: 'sessions.list', params: const {});
  final list = (res['items'] as List? ?? const [])
      .cast<Map>()
      .map((m) => Session.fromJson(m.cast<String, dynamic>()))
      .toList();
  // Subscribe to live updates
  await _rpc!.request(method: 'sessions.subscribe', params: const {});
  return list;
}

@override
Stream<SessionListEvent> watchSessions() {
  _ensureRouter();
  return _router!.sessionsStream();
}

@override
Future<void> renameSession(String id, String title) async {
  await _rpc!.request(
    method: 'sessions.patch',
    params: {'id': id, 'title': title},
  );
}

@override
Future<void> deleteSession(String id) async {
  await _rpc!.request(method: 'sessions.delete', params: {'id': id});
}

@override
Future<List<Message>> loadHistory(String sessionId, {String? cursor}) async {
  final res = await _rpc!.request(
    method: 'chat.history',
    params: {'sessionId': sessionId, if (cursor != null) 'cursor': cursor},
  );
  return (res['items'] as List? ?? const [])
      .cast<Map>()
      .map((m) => Message.fromJson(m.cast<String, dynamic>()))
      .toList();
}

@override
Future<void> sendMessage({
  required String sessionId,
  required String text,
  required String requestId,
}) async {
  await _rpc!.request(method: 'chat.send', params: {
    'sessionId': sessionId,
    'text': text,
    'requestId': requestId, // adjust per captured shape
  });
}

@override
Stream<ChatStreamEvent> watchChat(String sessionId) {
  _ensureRouter();
  return _router!.chatStream(sessionId);
}

@override
Future<void> abort(String requestId) async {
  await _rpc!.request(method: 'chat.abort', params: {'requestId': requestId});
}
```

Add the `EventRouter` import to the top of the file.

- [ ] **Step 2: Analyze**

```bash
flutter analyze
```
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add lib/data/gateway/agents/openclaw/openclaw_client.dart
git commit -m "feat(openclaw): implement chat + sessions methods"
```

---

## Phase 4 — Repositories

### Task 7: `SessionRepository` (gateway + cache)

**Files:**
- Create: `lib/domain/repositories/session_repository.dart`
- Create: `test/domain/repositories/session_repository_test.dart`

- [ ] **Step 1: Failing test (uses fake gateway)**

Create `test/domain/repositories/session_repository_test.dart`:
```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stt_tts/data/cache/local_store.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/domain/repositories/session_repository.dart';

class FakeGateway implements GatewayClient {
  final List<Session> sessions = [];
  final _events = StreamController<SessionListEvent>.broadcast();

  @override
  Future<List<Session>> listSessions() async => sessions;
  @override
  Stream<SessionListEvent> watchSessions() => _events.stream;
  @override
  Future<void> renameSession(String id, String title) async {
    final i = sessions.indexWhere((s) => s.id == id);
    sessions[i] = sessions[i].copyWith(title: title);
    _events.add(SessionUpdated(sessions[i]));
  }
  @override
  Future<void> deleteSession(String id) async {
    sessions.removeWhere((s) => s.id == id);
    _events.add(SessionRemoved(id));
  }
  // unused for this test
  @override Future<HelloResult> connect(_) => throw UnimplementedError();
  @override Future<void> disconnect() => throw UnimplementedError();
  @override Stream<ConnectionState> get connectionState => const Stream.empty();
  @override GatewayCapabilities get capabilities => const GatewayCapabilities(streaming: true, sources: true, plugins: true);
  @override Future<List<Message>> loadHistory(_, {String? cursor}) => throw UnimplementedError();
  @override Future<void> sendMessage({required String sessionId, required String text, required String requestId}) => throw UnimplementedError();
  @override Stream<ChatStreamEvent> watchChat(String sessionId) => const Stream.empty();
  @override Future<void> abort(String requestId) => throw UnimplementedError();
}

void main() {
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });

  test('initial load merges gateway items into cache, returns sorted', () async {
    final store = LocalStore();
    await store.openInMemory();
    final gw = FakeGateway()..sessions.addAll([
      Session(id: 'A', title: 'A', updatedAt: DateTime(2026, 4, 1),
          pinned: false, hasVoiceMessages: false, isCron: false),
      Session(id: 'B', title: 'B', updatedAt: DateTime(2026, 4, 5),
          pinned: false, hasVoiceMessages: false, isCron: false),
    ]);
    final repo = SessionRepository(gw, store);
    final list = await repo.refresh();
    expect(list.first.id, 'B'); // newer first
  });
}
```

- [ ] **Step 2: Run to confirm fail**

```bash
flutter test test/domain/repositories/session_repository_test.dart
```

- [ ] **Step 3: Implement**

Create `lib/domain/repositories/session_repository.dart`:
```dart
import 'package:stt_tts/data/cache/local_store.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/domain/models/session.dart';

class SessionRepository {
  SessionRepository(this._gw, this._cache);
  final GatewayClient _gw;
  final LocalStore _cache;

  Future<List<Session>> refresh() async {
    final fresh = await _gw.listSessions();
    final cached = {for (final s in await _cache.listSessions()) s.id: s};
    final merged = fresh
        .map((s) => s.copyWith(pinned: cached[s.id]?.pinned ?? false))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final s in merged) {
      await _cache.upsertSession(s);
    }
    return merged;
  }

  Stream<SessionListEvent> watch() => _gw.watchSessions();

  Future<void> rename(String id, String title) => _gw.renameSession(id, title);
  Future<void> delete(String id) async {
    await _gw.deleteSession(id);
    await _cache.deleteSession(id);
  }

  Future<void> setPinned(String id, bool pinned) async {
    await _cache.setPinned(id, pinned);
  }
}
```

- [ ] **Step 4: Run to verify pass + commit**

```bash
flutter test test/domain/repositories/session_repository_test.dart
git add lib/domain/repositories/session_repository.dart test/domain/repositories/session_repository_test.dart
git commit -m "feat(repo): SessionRepository merging gateway + local cache"
```

---

### Task 8: `ChatRepository` (streaming aggregator)

**Files:**
- Create: `lib/domain/repositories/chat_repository.dart`
- Create: `test/domain/repositories/chat_repository_test.dart`

- [ ] **Step 1: Failing test**

Create `test/domain/repositories/chat_repository_test.dart`:
```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/domain/repositories/chat_repository.dart';

class FakeGw implements GatewayClient {
  final inbound = StreamController<ChatStreamEvent>.broadcast();
  final sent = <Map<String, String>>[];
  @override
  Future<void> sendMessage({required String sessionId, required String text, required String requestId}) async {
    sent.add({'sessionId': sessionId, 'text': text, 'requestId': requestId});
  }
  @override
  Stream<ChatStreamEvent> watchChat(String sessionId) => inbound.stream;
  @override
  Future<void> abort(String requestId) async {}
  // others
  @override Future<HelloResult> connect(_) => throw UnimplementedError();
  @override Future<void> disconnect() => throw UnimplementedError();
  @override Stream<ConnectionState> get connectionState => const Stream.empty();
  @override GatewayCapabilities get capabilities => const GatewayCapabilities(streaming: true, sources: true, plugins: true);
  @override Future<List<Session>> listSessions() async => const [];
  @override Stream<SessionListEvent> watchSessions() => const Stream.empty();
  @override Future<void> renameSession(_, __) async {}
  @override Future<void> deleteSession(_) async {}
  @override Future<List<Message>> loadHistory(_, {String? cursor}) async => const [];
}

void main() {
  test('aggregates deltas into a streaming Message', () async {
    final gw = FakeGw();
    final repo = ChatRepository(gw);
    final updates = <Message>[];
    repo.watch('S1').listen(updates.add);

    gw.inbound.add(const ChatDelta(messageId: 'M', text: 'Hi'));
    gw.inbound.add(const ChatDelta(messageId: 'M', text: ', there'));
    gw.inbound.add(ChatFinal(message: Message(
      id: 'M', sessionId: 'S1', role: Role.assistant, text: 'Hi, there',
      parts: const [], createdAt: DateTime(2026), source: MessageSource.typedChat,
      streaming: StreamingState.finalized,
    )));
    await Future.delayed(Duration.zero);

    expect(updates.last.text, 'Hi, there');
    expect(updates.last.streaming, StreamingState.finalized);
  });
}
```

- [ ] **Step 2: Run to confirm fail**

```bash
flutter test test/domain/repositories/chat_repository_test.dart
```

- [ ] **Step 3: Implement**

Create `lib/domain/repositories/chat_repository.dart`:
```dart
import 'dart:async';

import 'package:stt_tts/core/ids.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/domain/models/message.dart';

class ChatRepository {
  ChatRepository(this._gw);
  final GatewayClient _gw;
  final Map<String, Message> _streamingByMessageId = {};

  Future<List<Message>> loadHistory(String sessionId, {String? cursor}) =>
      _gw.loadHistory(sessionId, cursor: cursor);

  Stream<Message> watch(String sessionId) async* {
    await for (final ev in _gw.watchChat(sessionId)) {
      switch (ev) {
        case ChatDelta():
          final cur = _streamingByMessageId[ev.messageId] ??
              Message(
                id: ev.messageId, sessionId: sessionId, role: Role.assistant,
                text: '', parts: const [], createdAt: DateTime.now(),
                source: MessageSource.typedChat, streaming: StreamingState.partial,
              );
          final next = cur.appendDelta(ev.text);
          _streamingByMessageId[ev.messageId] = next;
          yield next;
        case ChatFinal():
          _streamingByMessageId.remove(ev.message.id);
          yield ev.message.finalize();
        case ChatSourcesEvent():
          final cur = _streamingByMessageId[ev.messageId];
          if (cur != null) {
            final next = cur.finalize(withSources: ev.sources);
            _streamingByMessageId[ev.messageId] = next;
            yield next;
          }
        case ChatToolWorking():
          // UI uses this via a separate stream from gateway; ignore here
          break;
        case ChatFailed():
          final cur = _streamingByMessageId[ev.messageId];
          if (cur != null) {
            yield cur.fail();
            _streamingByMessageId.remove(ev.messageId);
          }
      }
    }
  }

  Future<String> send({required String sessionId, required String text}) async {
    final reqId = newRequestId();
    await _gw.sendMessage(sessionId: sessionId, text: text, requestId: reqId);
    return reqId;
  }

  Future<void> abort(String requestId) => _gw.abort(requestId);
}
```

- [ ] **Step 4: Run + commit**

```bash
flutter test test/domain/repositories/chat_repository_test.dart
git add lib/domain/repositories/chat_repository.dart test/domain/repositories/chat_repository_test.dart
git commit -m "feat(repo): ChatRepository streaming aggregator"
```

---

## Phase 5 — Riverpod state

### Task 9: `sessionsProvider` (list, filter chips, search)

**Files:**
- Create: `lib/state/sessions_provider.dart`

- [ ] **Step 1: Implement (covered later by widget tests)**

Create `lib/state/sessions_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/data/cache/local_store.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/domain/repositories/session_repository.dart';
import 'package:stt_tts/state/connection_provider.dart';

enum SessionFilter { all, voice, text, pinned }

final localStoreProvider = FutureProvider<LocalStore>((ref) async {
  final store = LocalStore();
  await store.open();
  return store;
});

final sessionRepositoryProvider = FutureProvider<SessionRepository>((ref) async {
  final store = await ref.watch(localStoreProvider.future);
  final gw = ref.watch(gatewayClientProvider);
  return SessionRepository(gw, store);
});

class SessionsState {
  const SessionsState({
    required this.items,
    required this.filter,
    required this.query,
  });
  final List<Session> items;
  final SessionFilter filter;
  final String query;

  SessionsState copyWith({List<Session>? items, SessionFilter? filter, String? query}) =>
      SessionsState(
        items: items ?? this.items,
        filter: filter ?? this.filter,
        query: query ?? this.query,
      );

  List<Session> get filtered {
    Iterable<Session> out = items;
    switch (filter) {
      case SessionFilter.voice: out = out.where((s) => s.hasVoiceMessages); break;
      case SessionFilter.text: out = out.where((s) => !s.hasVoiceMessages); break;
      case SessionFilter.pinned: out = out.where((s) => s.pinned); break;
      case SessionFilter.all: break;
    }
    if (query.trim().isNotEmpty) {
      final q = query.toLowerCase();
      out = out.where((s) =>
          s.title.toLowerCase().contains(q) ||
          (s.lastPreview ?? '').toLowerCase().contains(q));
    }
    final list = out.toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return list;
  }
}

class SessionsNotifier extends StateNotifier<AsyncValue<SessionsState>> {
  SessionsNotifier(this._ref) : super(const AsyncValue.loading()) {
    _bootstrap();
  }
  final Ref _ref;

  Future<void> _bootstrap() async {
    try {
      final repo = await _ref.read(sessionRepositoryProvider.future);
      final list = await repo.refresh();
      state = AsyncValue.data(SessionsState(
        items: list, filter: SessionFilter.all, query: '',
      ));
      // Live updates
      repo.watch().listen((ev) {
        final cur = state.valueOrNull;
        if (cur == null) return;
        final list = [...cur.items];
        switch (ev) {
          case SessionAdded(): list.add(ev.session); break;
          case SessionUpdated():
            final i = list.indexWhere((s) => s.id == ev.session.id);
            if (i >= 0) list[i] = ev.session; else list.add(ev.session);
            break;
          case SessionRemoved():
            list.removeWhere((s) => s.id == ev.id);
        }
        state = AsyncValue.data(cur.copyWith(items: list));
      });
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void setFilter(SessionFilter f) {
    final cur = state.valueOrNull;
    if (cur != null) state = AsyncValue.data(cur.copyWith(filter: f));
  }

  void setQuery(String q) {
    final cur = state.valueOrNull;
    if (cur != null) state = AsyncValue.data(cur.copyWith(query: q));
  }

  Future<void> rename(String id, String title) async {
    final repo = await _ref.read(sessionRepositoryProvider.future);
    await repo.rename(id, title);
  }

  Future<void> delete(String id) async {
    final repo = await _ref.read(sessionRepositoryProvider.future);
    await repo.delete(id);
  }

  Future<void> togglePin(String id) async {
    final repo = await _ref.read(sessionRepositoryProvider.future);
    final cur = state.valueOrNull?.items.firstWhere((s) => s.id == id);
    if (cur == null) return;
    await repo.setPinned(id, !cur.pinned);
    final next = state.valueOrNull?.items
        .map((s) => s.id == id ? s.copyWith(pinned: !s.pinned) : s)
        .toList();
    if (next != null) {
      state = AsyncValue.data(state.value!.copyWith(items: next));
    }
  }
}

final sessionsProvider = StateNotifierProvider<SessionsNotifier, AsyncValue<SessionsState>>(
  (ref) => SessionsNotifier(ref),
);
```

- [ ] **Step 2: Analyze + commit**

```bash
flutter analyze && git add lib/state/sessions_provider.dart && git commit -m "feat(state): sessions provider with filter + search"
```

---

### Task 10: `messagesProvider` family (per session)

**Files:**
- Create: `lib/state/messages_provider.dart`

- [ ] **Step 1: Implement**

Create `lib/state/messages_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/domain/repositories/chat_repository.dart';
import 'package:stt_tts/state/connection_provider.dart';

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(gatewayClientProvider)),
);

class MessagesState {
  const MessagesState({required this.history, required this.streaming});
  final List<Message> history;
  final Message? streaming;

  List<Message> get all =>
      streaming == null ? history : [...history, streaming!];
}

class MessagesNotifier extends StateNotifier<AsyncValue<MessagesState>> {
  MessagesNotifier(this._ref, this.sessionId) : super(const AsyncValue.loading()) {
    _bootstrap();
  }
  final Ref _ref;
  final String sessionId;
  String? _activeRequestId;

  Future<void> _bootstrap() async {
    try {
      final repo = _ref.read(chatRepositoryProvider);
      final hist = await repo.loadHistory(sessionId);
      state = AsyncValue.data(MessagesState(history: hist, streaming: null));

      repo.watch(sessionId).listen((m) {
        final cur = state.valueOrNull;
        if (cur == null) return;
        if (m.streaming == StreamingState.finalized || m.streaming == StreamingState.failed) {
          state = AsyncValue.data(MessagesState(
            history: [...cur.history, m],
            streaming: null,
          ));
        } else {
          state = AsyncValue.data(MessagesState(
            history: cur.history, streaming: m,
          ));
        }
      });
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> send(String text) async {
    final repo = _ref.read(chatRepositoryProvider);
    final cur = state.valueOrNull;
    if (cur == null) return;
    // Optimistic user bubble
    final userMsg = Message(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      sessionId: sessionId,
      role: Role.user, text: text, parts: const [],
      createdAt: DateTime.now(), source: MessageSource.typedChat,
      streaming: StreamingState.finalized,
    );
    state = AsyncValue.data(MessagesState(
      history: [...cur.history, userMsg], streaming: null,
    ));
    _activeRequestId = await repo.send(sessionId: sessionId, text: text);
  }

  Future<void> abort() async {
    if (_activeRequestId == null) return;
    await _ref.read(chatRepositoryProvider).abort(_activeRequestId!);
    _activeRequestId = null;
  }
}

final messagesProvider = StateNotifierProvider.family<
    MessagesNotifier, AsyncValue<MessagesState>, String>(
  (ref, sessionId) => MessagesNotifier(ref, sessionId),
);
```

- [ ] **Step 2: Analyze + commit**

```bash
flutter analyze && git add lib/state/messages_provider.dart && git commit -m "feat(state): per-session messages provider with streaming aggregation"
```

---

### Task 11: Auto-reconnect on app launch

**Files:**
- Modify: `lib/state/connection_provider.dart`

- [ ] **Step 1: Add auto-reconnect logic**

Append to `connection_provider.dart`:
```dart
final autoReconnectProvider = FutureProvider<bool>((ref) async {
  final store = ref.read(secureStoreProvider);
  final url = await store.read('oc.wsUrl');
  final deviceToken = await store.read('oc.deviceToken');
  if (url == null || deviceToken == null) return false;
  final client = ref.read(gatewayClientProvider);
  try {
    await client.connect(ConnectionConfig(wsUrl: url, deviceToken: deviceToken));
    return true;
  } catch (_) {
    return false;
  }
});
```

Modify `main.dart` to wait on this provider before deciding the home screen — easiest is to add a tiny "splash" screen that watches `autoReconnectProvider`:

Create `lib/ui/onboarding/splash_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/connection_provider.dart';
import 'package:stt_tts/ui/onboarding/welcome_screen.dart';
import 'package:stt_tts/ui/shell/home_shell.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoConnected = ref.watch(autoReconnectProvider);
    return autoConnected.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: OcColors.accent)),
      ),
      data: (ok) => ok ? const HomeShell() : const WelcomeScreen(),
      error: (_, __) => const WelcomeScreen(),
    );
  }
}
```

Update `lib/app.dart` to show `SplashScreen` instead of `WelcomeScreen`.

- [ ] **Step 2: Analyze + commit**

```bash
flutter analyze
git add lib/state/connection_provider.dart lib/ui/onboarding/splash_screen.dart lib/app.dart
git commit -m "feat(state): auto-reconnect on app launch with persisted deviceToken"
```

---

## Phase 6 — Sessions UI

### Task 12: `SessionsDrawer` + row + search bar + filter chips

**Files:**
- Create: `lib/ui/sessions/sessions_drawer.dart`
- Create: `lib/ui/sessions/session_row.dart`
- Create: `lib/ui/sessions/session_search_bar.dart`
- Create: `lib/ui/sessions/session_actions_sheet.dart`

> Reference the wireframe at `.superpowers/brainstorm/30000-1777434780/content/sessions-list-v2.html` for exact visual styling.

- [ ] **Step 1: Implement `SessionRow` (row widget)**

Create `lib/ui/sessions/session_row.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/session.dart';

class SessionRow extends StatelessWidget {
  const SessionRow({super.key, required this.session, required this.onTap, required this.onLongPress});
  final Session session;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: OcColors.overlayTint,
                ),
                child: Icon(
                  session.hasVoiceMessages ? Icons.mic : Icons.chat_bubble_outline,
                  color: OcColors.textSubtitle, size: 14,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            session.title,
                            style: const TextStyle(
                              color: OcColors.textPrimary,
                              fontSize: 13, fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _humanTime(session.updatedAt),
                          style: const TextStyle(color: OcColors.textMeta, fontSize: 10),
                        ),
                      ],
                    ),
                    if (session.lastPreview != null)
                      Text(
                        session.lastPreview!,
                        style: const TextStyle(color: OcColors.textSubtitle, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (session.pinned)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Icon(Icons.push_pin, size: 11, color: OcColors.warn),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _humanTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inDays < 1) return DateFormat.Hm().format(t);
    if (diff.inDays < 2) return 'Yesterday';
    if (diff.inDays < 7) return DateFormat.E().format(t);
    return DateFormat.MMMd().format(t);
  }
}
```

- [ ] **Step 2: Implement search bar + filter chips**

Create `lib/ui/sessions/session_search_bar.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/sessions_provider.dart';

class SessionSearchBar extends ConsumerStatefulWidget {
  const SessionSearchBar({super.key});
  @override
  ConsumerState<SessionSearchBar> createState() => _S();
}
class _S extends ConsumerState<SessionSearchBar> {
  final _c = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: OcColors.overlayTint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OcColors.borderTint),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(Icons.search, color: OcColors.textMeta, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _c,
                style: const TextStyle(color: OcColors.textPrimary, fontSize: 12),
                decoration: const InputDecoration(
                  hintText: 'Search conversations…',
                  hintStyle: TextStyle(color: OcColors.textMeta),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: (v) => ref.read(sessionsProvider.notifier).setQuery(v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FilterChips extends ConsumerWidget {
  const FilterChips({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(sessionsProvider).valueOrNull?.filter ?? SessionFilter.all;
    Widget chip(String label, SessionFilter f) {
      final on = filter == f;
      return GestureDetector(
        onTap: () => ref.read(sessionsProvider.notifier).setFilter(f),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: on ? const Color(0x2D6CB0FF) : OcColors.overlayTint,
            border: Border.all(color: on ? OcColors.accent.withOpacity(0.4) : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: TextStyle(
            color: on ? OcColors.accent : OcColors.textSubtitle,
            fontSize: 11,
          )),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        chip('All', SessionFilter.all),
        chip('Voice', SessionFilter.voice),
        chip('Text', SessionFilter.text),
        chip('Pinned', SessionFilter.pinned),
      ]),
    );
  }
}
```

- [ ] **Step 3: Implement actions sheet**

Create `lib/ui/sessions/session_actions_sheet.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/state/sessions_provider.dart';

void showSessionActions(BuildContext context, Session session, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    backgroundColor: OcColors.surface,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(session.pinned ? Icons.push_pin_outlined : Icons.push_pin),
            iconColor: OcColors.textPrimary,
            title: Text(session.pinned ? 'Unpin' : 'Pin', style: const TextStyle(color: OcColors.textPrimary)),
            onTap: () {
              Navigator.pop(context);
              ref.read(sessionsProvider.notifier).togglePin(session.id);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit, color: OcColors.textPrimary),
            title: const Text('Rename', style: TextStyle(color: OcColors.textPrimary)),
            onTap: () async {
              Navigator.pop(context);
              final controller = TextEditingController(text: session.title);
              final newTitle = await showDialog<String>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: OcColors.surface,
                  title: const Text('Rename', style: TextStyle(color: OcColors.textPrimary)),
                  content: TextField(controller: controller, autofocus: true),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('OK')),
                  ],
                ),
              );
              if (newTitle != null && newTitle.trim().isNotEmpty) {
                await ref.read(sessionsProvider.notifier).rename(session.id, newTitle.trim());
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: OcColors.danger),
            title: const Text('Delete', style: TextStyle(color: OcColors.danger)),
            onTap: () async {
              Navigator.pop(context);
              await ref.read(sessionsProvider.notifier).delete(session.id);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 4: Implement `SessionsDrawer`**

Create `lib/ui/sessions/sessions_drawer.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:stt_tts/ui/sessions/session_actions_sheet.dart';
import 'package:stt_tts/ui/sessions/session_row.dart';
import 'package:stt_tts/ui/sessions/session_search_bar.dart';

class SessionsDrawer extends ConsumerWidget {
  const SessionsDrawer({super.key, required this.onPick});
  final void Function(String sessionId) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionsProvider);
    return Container(
      color: OcColors.bgBottom,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Conversations',
                      style: TextStyle(color: OcColors.textPrimary,
                        fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  Icon(Icons.add, color: OcColors.accent, size: 22),
                ],
              ),
            ),
            const SessionSearchBar(),
            const FilterChips(),
            Expanded(
              child: state.when(
                loading: () => const Center(child: CircularProgressIndicator(color: OcColors.accent)),
                error: (e, _) => Center(child: Text('$e', style: const TextStyle(color: OcColors.danger))),
                data: (s) {
                  final list = s.filtered;
                  if (list.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No conversations yet — tap a mic and start one.',
                          style: TextStyle(color: OcColors.textSubtitle), textAlign: TextAlign.center),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final session = list[i];
                      return SessionRow(
                        session: session,
                        onTap: () => onPick(session.id),
                        onLongPress: () => showSessionActions(context, session, ref),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze
git add lib/ui/sessions/
git commit -m "feat(ui): sessions drawer with search, filter, pin/rename/delete"
```

---

## Phase 7 — Chat UI

### Task 13: `MessageBubble` + markdown renderer + sources pill + sheet

**Files:**
- Create: `lib/ui/chat/markdown_renderer.dart`
- Create: `lib/ui/chat/message_bubble.dart`
- Create: `lib/ui/chat/sources_pill.dart`
- Create: `lib/ui/chat/sources_sheet.dart`
- Create: `lib/ui/chat/working_indicator.dart`

- [ ] **Step 1: Markdown renderer config**

Create `lib/ui/chat/markdown_renderer.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:stt_tts/core/theme.dart';

MarkdownStyleSheet ocMarkdownStyle(BuildContext context) =>
    MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: const TextStyle(color: OcColors.textBody, fontSize: 13, height: 1.45),
      code: const TextStyle(
        color: OcColors.accent,
        backgroundColor: Color(0xFF111727),
        fontFamily: 'monospace',
        fontSize: 12,
      ),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF111727),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: OcColors.borderTint),
      ),
      h1: const TextStyle(color: OcColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
      h2: const TextStyle(color: OcColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
      h3: const TextStyle(color: OcColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
    );

/// Strip markdown for TTS reading. (Used by voice mode in slice 1C.)
String stripMarkdown(String src) =>
    src.replaceAllMapped(RegExp(r'(\*\*|\*|_|`)'), (_) => '')
       .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1) ?? '')
       .replaceAllMapped(RegExp(r'^#+\s*', multiLine: true), (_) => '');
```

- [ ] **Step 2: Sources pill + sheet**

Create `lib/ui/chat/sources_pill.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/ui/chat/sources_sheet.dart';

class SourcesPill extends StatelessWidget {
  const SourcesPill({super.key, required this.sources});
  final List<Source> sources;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: GestureDetector(
        onTap: () => showSourcesSheet(context, sources),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: OcColors.overlayTint,
            border: Border.all(color: OcColors.borderTint),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.attachment, color: OcColors.accent, size: 12),
              const SizedBox(width: 6),
              Text('${sources.length} source${sources.length == 1 ? '' : 's'}',
                style: const TextStyle(color: OcColors.textSubtitle, fontSize: 11)),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, color: OcColors.textMeta, size: 12),
            ],
          ),
        ),
      ),
    );
  }
}
```

Create `lib/ui/chat/sources_sheet.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:url_launcher/url_launcher.dart';

void showSourcesSheet(BuildContext context, List<Source> sources) {
  showModalBottomSheet(
    context: context,
    backgroundColor: OcColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: OcColors.borderTint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Sources',
              style: TextStyle(color: OcColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 10),
            ...sources.map((s) => _SourceRow(s)),
          ],
        ),
      ),
    ),
  );
}

class _SourceRow extends StatelessWidget {
  const _SourceRow(this.source);
  final Source source;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final uri = Uri.tryParse(source.url);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: OcColors.overlayTint,
            border: Border.all(color: OcColors.borderTint),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  color: const Color(0x2D6CB0FF),
                ),
                child: const Icon(Icons.public, color: OcColors.accent, size: 13),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(source.title,
                      style: const TextStyle(color: OcColors.textPrimary, fontSize: 12),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (source.domain != null)
                      Text(source.domain!,
                        style: const TextStyle(color: OcColors.textSubtitle, fontSize: 10)),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, color: OcColors.textMeta, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}
```

Add `url_launcher: ^6.3.0` to dependencies. `flutter pub get`.

- [ ] **Step 3: Working indicator**

Create `lib/ui/chat/working_indicator.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

class WorkingIndicator extends StatefulWidget {
  const WorkingIndicator({super.key, this.label = 'Looking it up'});
  final String label;
  @override
  State<WorkingIndicator> createState() => _S();
}

class _S extends State<WorkingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4, bottom: 6),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.label, style: const TextStyle(color: OcColors.accent, fontSize: 11)),
              const SizedBox(width: 6),
              ...List.generate(3, (i) {
                final phase = (_c.value + i / 6) % 1.0;
                return Container(
                  margin: const EdgeInsets.only(right: 2),
                  width: 4, height: 4,
                  decoration: BoxDecoration(
                    color: OcColors.accent.withOpacity(0.3 + 0.7 * (1 - (phase - 0.5).abs() * 2).clamp(0, 1).toDouble()),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: `MessageBubble`**

Create `lib/ui/chat/message_bubble.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/ui/chat/markdown_renderer.dart';
import 'package:stt_tts/ui/chat/sources_pill.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});
  final Message message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == Role.user;
    final bg = isUser ? OcColors.accent : OcColors.overlayTint;
    final fg = isUser ? OcColors.bgBottom : OcColors.textBody;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final crossAxis = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
          child: Column(
            crossAxisAlignment: crossAxis,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isUser ? Colors.transparent : OcColors.borderTint),
                ),
                child: isUser
                    ? Text(message.text ?? '', style: TextStyle(color: fg, fontSize: 12))
                    : MarkdownBody(
                        data: message.text ?? '',
                        styleSheet: ocMarkdownStyle(context),
                        selectable: true,
                      ),
              ),
              if (!isUser) SourcesPill(sources: message.sources),
              if (message.streaming == StreamingState.failed)
                const Padding(
                  padding: EdgeInsets.only(top: 4, left: 4),
                  child: Text('Send failed — tap to retry',
                    style: TextStyle(color: OcColors.danger, fontSize: 10)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze
git add lib/ui/chat/ pubspec.yaml pubspec.lock
git commit -m "feat(ui): message bubble + markdown + sources pill + working indicator"
```

---

### Task 14: `ChatComposer` + `ChatScreen`

**Files:**
- Create: `lib/ui/chat/chat_composer.dart`
- Create: `lib/ui/chat/chat_screen.dart`

- [ ] **Step 1: Composer**

Create `lib/ui/chat/chat_composer.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key, required this.onSend, required this.onMicTap, required this.busy,
    required this.onAbort,
  });
  final void Function(String text) onSend;
  final VoidCallback onMicTap;
  final VoidCallback onAbort;
  final bool busy;

  @override
  State<ChatComposer> createState() => _S();
}
class _S extends State<ChatComposer> {
  final _c = TextEditingController();
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x0F78B4FF),
        border: const Border(top: BorderSide(color: OcColors.borderTint)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: widget.onMicTap,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0E1424),
                border: Border.all(color: const Color(0xB36CB0FF), width: 1.5),
                boxShadow: const [BoxShadow(color: Color(0x736CB0FF), blurRadius: 12)],
              ),
              child: const Icon(Icons.mic, color: OcColors.accent, size: 16),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _c,
              minLines: 1,
              maxLines: 5,
              style: const TextStyle(color: OcColors.textPrimary, fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'Type a message…',
                hintStyle: TextStyle(color: OcColors.textMeta),
                filled: true,
                fillColor: Color(0x0FFFFFFF),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                  borderSide: BorderSide(color: OcColors.borderTint),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                  borderSide: BorderSide(color: OcColors.borderTint),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              if (widget.busy) {
                widget.onAbort();
              } else {
                final t = _c.text.trim();
                if (t.isEmpty) return;
                widget.onSend(t);
                _c.clear();
              }
            },
            child: Container(
              width: 32, height: 32,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: OcColors.accent),
              child: Icon(widget.busy ? Icons.stop : Icons.arrow_upward,
                color: OcColors.bgBottom, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Chat screen**

Create `lib/ui/chat/chat_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/state/messages_provider.dart';
import 'package:stt_tts/ui/chat/chat_composer.dart';
import 'package:stt_tts/ui/chat/message_bubble.dart';
import 'package:stt_tts/ui/chat/working_indicator.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(messagesProvider(sessionId));
    final notifier = ref.read(messagesProvider(sessionId).notifier);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: OcColors.textPrimary,
        title: const Text('Chat'),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: ocBackgroundGradient),
        child: Column(
          children: [
            Expanded(
              child: state.when(
                loading: () => const Center(child: CircularProgressIndicator(color: OcColors.accent)),
                error: (e, _) => Center(child: Text('$e', style: const TextStyle(color: OcColors.danger))),
                data: (s) {
                  final all = s.all;
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: all.length + (s.streaming != null && s.streaming!.text!.isEmpty ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i < all.length) {
                        return MessageBubble(message: all[i]);
                      }
                      return const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: WorkingIndicator(),
                      );
                    },
                  );
                },
              ),
            ),
            ChatComposer(
              busy: state.valueOrNull?.streaming != null,
              onSend: notifier.send,
              onAbort: notifier.abort,
              onMicTap: () {/* hooked up in slice 1C */},
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Analyze + commit**

```bash
flutter analyze
git add lib/ui/chat/chat_composer.dart lib/ui/chat/chat_screen.dart
git commit -m "feat(ui): chat composer + chat screen"
```

---

## Phase 8 — Wire it all up

### Task 15: `HomeShell` (skeleton with sessions drawer + chat host)

**Files:**
- Create: `lib/ui/shell/home_shell.dart`
- Create: `lib/ui/widgets/connection_banner.dart`

> The voice-first home (mic ring as the hero) lands in slice 1C. For 1B, the home shell shows the sessions drawer on the left edge swipe and the chat thread for the currently-selected session in the body. Until a session is picked, body shows a placeholder.

- [ ] **Step 1: Connection banner**

Create `lib/ui/widgets/connection_banner.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/state/connection_provider.dart';

class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(connectionStateProvider).valueOrNull;
    if (s == ConnectionState.authenticated || s == null) return const SizedBox.shrink();
    final color = s == ConnectionState.failed ? OcColors.danger : OcColors.warn;
    final text = switch (s) {
      ConnectionState.connecting => 'Reconnecting…',
      ConnectionState.disconnected => '⚡ No connection — trying to reconnect',
      ConnectionState.failed => 'Connection failed',
      _ => '',
    };
    return Container(
      width: double.infinity,
      color: color.withOpacity(0.18),
      padding: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.center,
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
```

- [ ] **Step 2: Home shell**

Create `lib/ui/shell/home_shell.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/ui/chat/chat_screen.dart';
import 'package:stt_tts/ui/sessions/sessions_drawer.dart';
import 'package:stt_tts/ui/widgets/connection_banner.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _S();
}
class _S extends ConsumerState<HomeShell> {
  String? _activeSessionId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OcColors.bgBottom,
      drawer: SessionsDrawer(onPick: (id) {
        setState(() => _activeSessionId = id);
        Navigator.of(context).pop(); // close drawer
      }),
      body: Column(
        children: [
          const ConnectionBanner(),
          Expanded(
            child: _activeSessionId == null
                ? _PlaceholderHome()
                : ChatScreen(sessionId: _activeSessionId!),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderHome extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: ocBackgroundGradient),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.waving_hand_rounded, color: OcColors.accent, size: 38),
              SizedBox(height: 14),
              Text('Pick a conversation or open the menu',
                style: TextStyle(color: OcColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text('Voice mode arrives in slice 1C.',
                style: TextStyle(color: OcColors.textSubtitle, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Analyze + commit**

```bash
flutter analyze
git add lib/ui/shell/home_shell.dart lib/ui/widgets/connection_banner.dart
git commit -m "feat(ui): home shell with sessions drawer + chat host + connection banner"
```

---

## Phase 9 — End-to-end smoke

### Task 16: Smoke test against real OpenClaw

- [ ] **Step 1: Run on device**

```bash
flutter run
```

- [ ] **Step 2: Walk the path**

1. Pair if not already paired (1A's manual form)
2. After "You're in," replace the ready screen's button to navigate to `HomeShell` — temporarily hardcode `Navigator.pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()))`.
3. Open the drawer → sessions list loads (or "no conversations yet")
4. Tap "+" — for now, pre-create a session manually via `curl` against the gateway, since session creation isn't an explicit method we've wired (sessions auto-create on first `chat.send`)
5. Type "Hello" → see streaming reply
6. Tap Stop mid-stream → reply truncates
7. Long-press the session in the drawer → rename it → see updated title
8. Long-press again → delete → it disappears

- [ ] **Step 3: Fix any rough edges, commit**

```bash
git add -A && git commit -m "chore: slice 1B smoke test passes — chat + sessions working end-to-end"
```

---

## Self-review checklist

**Spec coverage:**
- §6 onboarding: covered by 1A's manual pair (re-used via auto-reconnect on launch)
- §7 data model: §1B Tasks 2 (Session, Message)
- §8 chat mode: Tasks 8, 13, 14
- §8.2 markdown: Task 13
- §8.3 tool calls/sources: Tasks 13 (pill, sheet) + Task 5 (event router)
- §11 sessions: Tasks 7, 9, 12
- §15 errors / reconnect: Task 11 (auto-reconnect), Task 15 (banner)

**Out of scope for 1B (covered later):**
- Voice mode (lift POC + 4 states + karaoke + voice commands) → 1C
- Wake word, settings, full error/empty state polish → 1D

**Placeholder scan:**
- Task 5 (event router) and Task 6 (chat method overrides) reference event/method names from the protocol-capture doc — these MUST be replaced with the real captured names. The names used in the plan (`chat.delta`, `chat.message`, `chat.sources`) are placeholders pending Task 0.1 of plan 1A.
- Task 16 mentions "pre-create a session via curl" — if the gateway requires explicit session creation (`sessions.create`?), the captured doc will tell us, and we update the plan accordingly.

**Type consistency:** `Session`, `Message`, `Source`, `ChatStreamEvent` and its subclasses, `SessionListEvent` and its subclasses, `SessionsState`, `MessagesState` — all defined in this plan and used consistently.
