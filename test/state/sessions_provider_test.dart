import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/cache/local_store.dart';
import 'package:stt_tts/data/gateway/connection_config.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/domain/repositories/session_repository.dart';
import 'package:stt_tts/state/repositories_provider.dart';
import 'package:stt_tts/state/sessions_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Session _s(String key, DateTime updatedAt, {bool pinned = false}) => Session(
      key: key,
      title: key,
      updatedAt: updatedAt,
      kind: 'direct',
      pinned: pinned,
    );

final _t0 = DateTime.utc(2026, 1, 1);
final _t1 = DateTime.utc(2026, 1, 2);
final _t2 = DateTime.utc(2026, 1, 3);

// ---------------------------------------------------------------------------
// Fake GatewayClient — minimal implementation for session provider tests.
// ---------------------------------------------------------------------------

class _FakeGatewayClient implements GatewayClient {
  List<Session> sessions = [];
  final _updatesCtrl = StreamController<Session>.broadcast();

  @override
  Future<List<Session>> listSessions() async => List.of(sessions);

  @override
  Stream<Session> watchSessionUpdates() => _updatesCtrl.stream;

  @override
  Future<void> patchSession(String sessionKey, {String? title}) async {}

  @override
  Future<void> deleteSession(String sessionKey) async {}

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
  // -------------------------------------------------------------------------
  // Test 1: SessionsState.visible applies filter + query correctly.
  // -------------------------------------------------------------------------
  test('SessionsState.visible applies filter and query correctly', () {
    final sessions = [
      _s('a', _t2, pinned: true)
          .copyWith(title: 'Alpha Chat'),
      _s('b', _t1)
          .copyWith(title: 'Beta Voice'),
      _s('c', _t0, pinned: false)
          .copyWith(title: 'Gamma Chat'),
    ];

    // No filter, no query → all sessions.
    final all = SessionsState(
      sessions: AsyncValue.data(sessions),
      filter: SessionFilter.all,
      query: '',
    );
    expect(all.visible.valueOrNull, sessions);

    // Query matches only 'Alpha Chat' and 'Gamma Chat'.
    final withQuery = all.copyWith(query: 'chat');
    final visible = withQuery.visible.valueOrNull!;
    expect(visible.map((s) => s.key).toList(), ['a', 'c']);

    // Pinned filter: only 'a' is pinned.
    final pinned = all.copyWith(filter: SessionFilter.pinned);
    final pinnedVisible = pinned.visible.valueOrNull!;
    expect(pinnedVisible.map((s) => s.key).toList(), ['a']);

    // Query + pinned filter → intersection.
    final both = all.copyWith(filter: SessionFilter.pinned, query: 'chat');
    final bothVisible = both.visible.valueOrNull!;
    expect(bothVisible.map((s) => s.key).toList(), ['a']);
  });

  // -------------------------------------------------------------------------
  // Test 2: SessionsController.setPinned reorders list optimistically.
  // -------------------------------------------------------------------------
  test('SessionsController.setPinned optimistically reorders list', () async {
    final gw = _FakeGatewayClient();
    // Gateway returns no sessions so refresh() doesn't interfere.
    gw.sessions = [];

    final store = InMemoryLocalStore();
    await store.open();

    // Pre-populate the cache with three sessions — none pinned.
    final sessions = [
      _s('newest', _t2),
      _s('middle', _t1),
      _s('oldest', _t0),
    ];
    for (final s in sessions) {
      await store.upsertSession(s);
    }

    final repo = SessionRepository(gw, store);

    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        sessionRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    // Wait for bootstrap to finish: cached sessions load + refresh attempt.
    // The refresh call (listSessions → []) will produce data([]), which means
    // the cached list gets overwritten by an empty list. So we seed the state
    // manually instead by waiting for loading to complete and then asserting
    // after setPinned.
    //
    // Better approach: give the gateway the same sessions so refresh() returns
    // them and the state is data([newest, middle, oldest]).
    gw.sessions = sessions;

    // Drain all microtasks / timers until the provider settles.
    await Future<void>.delayed(Duration.zero);
    // Give the bootstrap async chain a bit more time.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // Pin 'oldest' — it should jump to position 0 (pinned-first sort).
    final ctrl = container.read(sessionsProvider.notifier);
    await ctrl.setPinned('oldest', true);

    final list = container.read(sessionsProvider).sessions.valueOrNull;
    expect(list, isNotNull);

    final keys = list!.map((s) => s.key).toList();
    // 'oldest' (now pinned) must be first.
    expect(keys.first, 'oldest');
    // Remaining two are unpinned, ordered by updatedAt DESC.
    expect(keys.sublist(1), ['newest', 'middle']);
  });
}
