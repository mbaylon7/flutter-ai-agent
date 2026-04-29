import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/cache/local_store.dart';
import 'package:stt_tts/data/gateway/connection_config.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/domain/repositories/session_repository.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Session makeSession({
  required String key,
  required String title,
  required DateTime updatedAt,
  bool pinned = false,
  String kind = 'direct',
  String? lastPreview,
}) =>
    Session(
      key: key,
      title: title,
      updatedAt: updatedAt,
      kind: kind,
      pinned: pinned,
      lastPreview: lastPreview,
    );

// ---------------------------------------------------------------------------
// FakeGatewayClient
// ---------------------------------------------------------------------------

class FakeGatewayClient implements GatewayClient {
  List<Session> sessions = [];
  final StreamController<Session> _updatesController =
      StreamController<Session>.broadcast();

  StreamController<Session> get updates => _updatesController;

  // Recorded calls for assertion.
  final List<({String key, String? title})> patchCalls = [];
  final List<String> deleteCalls = [];

  @override
  Future<List<Session>> listSessions() async => List.of(sessions);

  @override
  Stream<Session> watchSessionUpdates() => _updatesController.stream;

  @override
  Future<void> patchSession(String sessionKey, {String? title}) async {
    patchCalls.add((key: sessionKey, title: title));
  }

  @override
  Future<void> deleteSession(String sessionKey) async {
    deleteCalls.add(sessionKey);
  }

  // --- chat / connection methods not exercised in session repo tests ---

  @override
  Future<HelloResult> connect(ConnectionConfig config) =>
      throw UnimplementedError();

  @override
  Future<void> disconnect() => throw UnimplementedError();

  @override
  Stream<ConnectionState> get connectionState => throw UnimplementedError();

  @override
  GatewayCapabilities get capabilities => throw UnimplementedError();

  @override
  Future<List<Message>> loadHistory(String sessionKey) =>
      throw UnimplementedError();

  @override
  Future<ChatRun> sendMessage({
    required String sessionKey,
    required String text,
    required String idempotencyKey,
  }) =>
      throw UnimplementedError();

  @override
  Stream<ChatStreamEvent> watchChat() => throw UnimplementedError();

  @override
  Future<void> abort(String runId) => throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late FakeGatewayClient gw;
  late InMemoryLocalStore store;
  late SessionRepository repo;

  setUp(() async {
    gw = FakeGatewayClient();
    store = InMemoryLocalStore();
    await store.open();
    repo = SessionRepository(gw, store);
  });

  tearDown(() async {
    await store.close();
    await gw.updates.close();
  });

  // -------------------------------------------------------------------------
  // 1. refresh() — sort + pin merge
  // -------------------------------------------------------------------------
  test(
    'refresh() returns gateway sessions sorted pinned-first then updatedAt DESC, '
    'with cached pin flag merged in',
    () async {
      // Pre-populate the cache with "older" session marked pinned.
      final cachedPinned = makeSession(
        key: 'agent:a',
        title: 'Alpha (old, pinned in cache)',
        updatedAt: DateTime.utc(2026, 1, 1),
        pinned: true,
      );
      await store.upsertSession(cachedPinned);

      // Gateway returns the same key (NOT pinned) + a newer second session.
      gw.sessions = [
        makeSession(
          key: 'agent:a',
          title: 'Alpha',
          updatedAt: DateTime.utc(2026, 1, 1),
          pinned: false, // gateway never knows about pins
        ),
        makeSession(
          key: 'agent:b',
          title: 'Beta (newer)',
          updatedAt: DateTime.utc(2026, 4, 1),
          pinned: false,
        ),
      ];

      final result = await repo.refresh();

      // Pinned session should come first even though it has older updatedAt.
      expect(result, hasLength(2));
      expect(result[0].key, equals('agent:a'));
      expect(result[0].pinned, isTrue, reason: 'cached pin flag must be merged');
      expect(result[1].key, equals('agent:b'));
    },
  );

  // -------------------------------------------------------------------------
  // 2. refresh() persists merged result back to the cache
  // -------------------------------------------------------------------------
  test('refresh() persists merged result back to the cache', () async {
    gw.sessions = [
      makeSession(
        key: 'agent:x',
        title: 'X',
        updatedAt: DateTime.utc(2026, 4, 29),
      ),
    ];

    await repo.refresh();

    final cached = await store.listSessions();
    expect(cached, hasLength(1));
    expect(cached.first.key, equals('agent:x'));
    expect(cached.first.title, equals('X'));
  });

  // -------------------------------------------------------------------------
  // 3. cachedSessions() — offline-first, no gateway call
  // -------------------------------------------------------------------------
  test(
    'cachedSessions() returns whatever is in the cache without hitting the gateway',
    () async {
      // Prime the cache directly (bypass the repo).
      await store.upsertSession(makeSession(
        key: 'local-only',
        title: 'Local',
        updatedAt: DateTime.utc(2026, 3, 15),
      ));

      // Gateway is empty — if cachedSessions() touched it the list would be empty.
      gw.sessions = [];

      final result = await repo.cachedSessions();
      expect(result, hasLength(1));
      expect(result.first.key, equals('local-only'));
    },
  );

  // -------------------------------------------------------------------------
  // 4. watchUpdates() — forwards events, merges cached pin flag
  // -------------------------------------------------------------------------
  test(
    'watchUpdates() forwards a gateway-emitted Session with cached pin flag merged in',
    () async {
      // Cache knows agent:c is pinned.
      await store.upsertSession(makeSession(
        key: 'agent:c',
        title: 'C',
        updatedAt: DateTime.utc(2026, 1, 1),
        pinned: true,
      ));

      // Subscribe AFTER cache is populated so the snapshot includes the pin.
      final updates = <Session>[];
      final sub = repo.watchUpdates().listen(updates.add);

      // Gateway emits an update for the same session (without pin flag).
      gw.updates.add(makeSession(
        key: 'agent:c',
        title: 'C — updated',
        updatedAt: DateTime.utc(2026, 4, 29),
        pinned: false,
      ));

      // Give the stream time to propagate.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      expect(updates, hasLength(1));
      expect(updates.first.key, equals('agent:c'));
      expect(updates.first.pinned, isTrue,
          reason: 'cached pin flag must be merged into stream events');
    },
  );

  // -------------------------------------------------------------------------
  // 5. rename() — calls patchSession with title
  // -------------------------------------------------------------------------
  test("rename(key, title) calls patchSession(key, title: title) exactly",
      () async {
    await repo.rename('agent:main:main', 'New Name');

    expect(gw.patchCalls, hasLength(1));
    expect(gw.patchCalls.first.key, equals('agent:main:main'));
    expect(gw.patchCalls.first.title, equals('New Name'));
  });

  // -------------------------------------------------------------------------
  // 6. delete() — calls deleteSession AND removes from cache
  // -------------------------------------------------------------------------
  test(
    'delete(key) calls deleteSession(key) AND removes from cache',
    () async {
      // Pre-populate cache.
      await store.upsertSession(makeSession(
        key: 'to-delete',
        title: 'Delete me',
        updatedAt: DateTime.utc(2026, 4, 29),
      ));

      await repo.delete('to-delete');

      expect(gw.deleteCalls, contains('to-delete'));

      final cached = await store.listSessions();
      expect(cached.where((s) => s.key == 'to-delete'), isEmpty);
    },
  );

  // -------------------------------------------------------------------------
  // 7. setPinned() — writes through cache only, no gateway call
  // -------------------------------------------------------------------------
  test(
    'setPinned(key, true) writes through cache only (no gateway call)',
    () async {
      await store.upsertSession(makeSession(
        key: 'agent:d',
        title: 'D',
        updatedAt: DateTime.utc(2026, 4, 29),
        pinned: false,
      ));

      await repo.setPinned('agent:d', true);

      // No gateway calls.
      expect(gw.patchCalls, isEmpty);
      expect(gw.deleteCalls, isEmpty);

      // Cache must reflect the new value.
      final cached = await store.listSessions();
      final session = cached.firstWhere((s) => s.key == 'agent:d');
      expect(session.pinned, isTrue);
    },
  );

  // =========================================================================
  // applySessionFilter tests
  // =========================================================================

  group('applySessionFilter', () {
    final sessions = [
      makeSession(
        key: 'k1',
        title: 'Hello World',
        updatedAt: DateTime.utc(2026, 4, 29),
        pinned: false,
        lastPreview: 'Some preview',
      ),
      makeSession(
        key: 'k2',
        title: 'Goodbye',
        updatedAt: DateTime.utc(2026, 4, 28),
        pinned: true,
        lastPreview: 'HELLO preview',
      ),
      makeSession(
        key: 'k3',
        title: 'No match',
        updatedAt: DateTime.utc(2026, 4, 27),
        pinned: false,
        lastPreview: 'Nothing relevant',
      ),
    ];

    // -----------------------------------------------------------------------
    // 8. Empty query + all returns input unchanged
    // -----------------------------------------------------------------------
    test('empty query + all returns input unchanged', () {
      final result = applySessionFilter(sessions);
      expect(result, equals(sessions));
    });

    // -----------------------------------------------------------------------
    // 9. Query matches title and preview case-insensitively
    // -----------------------------------------------------------------------
    test('query "hello" matches title and preview case-insensitively', () {
      final result = applySessionFilter(sessions, query: 'hello');
      // k1 has "Hello" in title; k2 has "HELLO" in preview.
      expect(result.map((s) => s.key).toList(),
          containsAll(['k1', 'k2']));
      // k3 should not be included.
      expect(result.map((s) => s.key), isNot(contains('k3')));
    });

    // -----------------------------------------------------------------------
    // 10. pinned filter excludes unpinned
    // -----------------------------------------------------------------------
    test('pinned filter excludes unpinned sessions', () {
      final result =
          applySessionFilter(sessions, filter: SessionFilter.pinned);
      expect(result.every((s) => s.pinned), isTrue);
      expect(result.map((s) => s.key).toList(), contains('k2'));
      expect(result, hasLength(1));
    });
  });
}
