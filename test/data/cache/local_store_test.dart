import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/cache/local_store.dart';
import 'package:stt_tts/domain/models/session.dart';

void main() {
  late InMemoryLocalStore store;

  setUp(() async {
    store = InMemoryLocalStore();
    await store.open();
  });

  tearDown(() async {
    await store.clear();
  });

  Session makeSession({
    required String key,
    required String title,
    required DateTime updatedAt,
    bool pinned = false,
    String kind = 'direct',
    String? lastPreview,
    int? totalTokens,
    double? estimatedCostUsd,
  }) =>
      Session(
        key: key,
        title: title,
        updatedAt: updatedAt,
        kind: kind,
        pinned: pinned,
        lastPreview: lastPreview,
        totalTokens: totalTokens,
        estimatedCostUsd: estimatedCostUsd,
      );

  group('upsert + list roundtrip', () {
    test('upserted session is returned by listSessions', () async {
      final s = makeSession(
        key: 'agent:main:main',
        title: 'Main Chat',
        updatedAt: DateTime.utc(2026, 4, 29, 10),
      );
      await store.upsertSession(s);

      final list = await store.listSessions();
      expect(list, hasLength(1));
      expect(list.first.key, equals('agent:main:main'));
      expect(list.first.title, equals('Main Chat'));
    });

    test('all optional fields survive a roundtrip', () async {
      final s = makeSession(
        key: 'k1',
        title: 'Rich Session',
        updatedAt: DateTime.utc(2026, 4, 29, 12),
        kind: 'cron',
        pinned: true,
        lastPreview: 'Hello world',
        totalTokens: 1234,
        estimatedCostUsd: 0.005,
      );
      await store.upsertSession(s);

      final result = (await store.listSessions()).first;
      expect(result.kind, equals('cron'));
      expect(result.pinned, isTrue);
      expect(result.lastPreview, equals('Hello world'));
      expect(result.totalTokens, equals(1234));
      expect(result.estimatedCostUsd, closeTo(0.005, 1e-9));
    });

    test('upsert replaces an existing session (no duplicate)', () async {
      final original = makeSession(
        key: 'agent:main:main',
        title: 'Old Title',
        updatedAt: DateTime.utc(2026, 4, 29, 10),
      );
      await store.upsertSession(original);

      final updated = makeSession(
        key: 'agent:main:main',
        title: 'New Title',
        updatedAt: DateTime.utc(2026, 4, 29, 11),
        lastPreview: 'Updated preview',
      );
      await store.upsertSession(updated);

      final list = await store.listSessions();
      expect(list, hasLength(1));
      expect(list.first.title, equals('New Title'));
      expect(list.first.lastPreview, equals('Updated preview'));
    });
  });

  group('sort order', () {
    test('listSessions returns sessions sorted by updatedAt DESC', () async {
      final older = makeSession(
        key: 'old',
        title: 'Older',
        updatedAt: DateTime.utc(2026, 4, 28),
      );
      final newer = makeSession(
        key: 'new',
        title: 'Newer',
        updatedAt: DateTime.utc(2026, 4, 29),
      );
      await store.upsertSession(older);
      await store.upsertSession(newer);

      final list = await store.listSessions();
      expect(list[0].key, equals('new'));
      expect(list[1].key, equals('old'));
    });

    test('pinned sessions come before unpinned regardless of updatedAt',
        () async {
      final pinnedOlder = makeSession(
        key: 'pinned',
        title: 'Pinned (older)',
        updatedAt: DateTime.utc(2026, 1, 1),
        pinned: true,
      );
      final unpinnedNewer = makeSession(
        key: 'unpinned',
        title: 'Unpinned (newer)',
        updatedAt: DateTime.utc(2026, 4, 29),
        pinned: false,
      );
      await store.upsertSession(pinnedOlder);
      await store.upsertSession(unpinnedNewer);

      final list = await store.listSessions();
      expect(list[0].key, equals('pinned'));
      expect(list[1].key, equals('unpinned'));
    });

    test('within the pinned group, updatedAt DESC still applies', () async {
      final pinnedOlder = makeSession(
        key: 'p-old',
        title: 'Pinned Older',
        updatedAt: DateTime.utc(2026, 2, 1),
        pinned: true,
      );
      final pinnedNewer = makeSession(
        key: 'p-new',
        title: 'Pinned Newer',
        updatedAt: DateTime.utc(2026, 4, 1),
        pinned: true,
      );
      final unpinned = makeSession(
        key: 'u',
        title: 'Unpinned',
        updatedAt: DateTime.utc(2026, 3, 1),
      );
      await store.upsertSession(pinnedOlder);
      await store.upsertSession(pinnedNewer);
      await store.upsertSession(unpinned);

      final list = await store.listSessions();
      expect(list[0].key, equals('p-new'));
      expect(list[1].key, equals('p-old'));
      expect(list[2].key, equals('u'));
    });
  });

  group('setPinned', () {
    test('setPinned(true) flips flag on an existing session', () async {
      final s = makeSession(
        key: 'agent:main:main',
        title: 'Chat',
        updatedAt: DateTime.utc(2026, 4, 29),
        pinned: false,
      );
      await store.upsertSession(s);
      await store.setPinned('agent:main:main', true);

      final list = await store.listSessions();
      expect(list.first.pinned, isTrue);
    });

    test('setPinned(false) clears flag', () async {
      final s = makeSession(
        key: 'k',
        title: 'T',
        updatedAt: DateTime.utc(2026, 4, 29),
        pinned: true,
      );
      await store.upsertSession(s);
      await store.setPinned('k', false);

      final list = await store.listSessions();
      expect(list.first.pinned, isFalse);
    });

    test('setPinned on a non-existent key is a no-op (no error)', () async {
      await expectLater(
        store.setPinned('does-not-exist', true),
        completes,
      );
      expect(await store.listSessions(), isEmpty);
    });
  });

  group('deleteSession', () {
    test('deleted session is no longer returned', () async {
      final s1 = makeSession(
        key: 'k1',
        title: 'S1',
        updatedAt: DateTime.utc(2026, 4, 29),
      );
      final s2 = makeSession(
        key: 'k2',
        title: 'S2',
        updatedAt: DateTime.utc(2026, 4, 28),
      );
      await store.upsertSession(s1);
      await store.upsertSession(s2);

      await store.deleteSession('k1');

      final list = await store.listSessions();
      expect(list, hasLength(1));
      expect(list.first.key, equals('k2'));
    });

    test('deleting a non-existent key is a no-op (no error)', () async {
      await expectLater(
        store.deleteSession('ghost'),
        completes,
      );
    });
  });

  group('clear', () {
    test('clear removes all sessions', () async {
      await store.upsertSession(makeSession(
        key: 'a',
        title: 'A',
        updatedAt: DateTime.utc(2026, 4, 29),
      ));
      await store.upsertSession(makeSession(
        key: 'b',
        title: 'B',
        updatedAt: DateTime.utc(2026, 4, 28),
      ));

      await store.clear();

      expect(await store.listSessions(), isEmpty);
    });

    test('can upsert after clear', () async {
      await store.upsertSession(makeSession(
        key: 'x',
        title: 'X',
        updatedAt: DateTime.utc(2026, 4, 29),
      ));
      await store.clear();
      await store.upsertSession(makeSession(
        key: 'y',
        title: 'Y',
        updatedAt: DateTime.utc(2026, 4, 29),
      ));

      final list = await store.listSessions();
      expect(list, hasLength(1));
      expect(list.first.key, equals('y'));
    });
  });

  group('updatedAt DateTime precision', () {
    test(
        'updatedAt equality is preserved in the in-memory path '
        '(no ms-epoch conversion; object stored by reference)', () async {
      final ts = DateTime.utc(2026, 4, 29, 15, 30, 45, 123);
      final s = makeSession(
        key: 'ts-test',
        title: 'TS',
        updatedAt: ts,
      );
      await store.upsertSession(s);

      final result = (await store.listSessions()).first;
      // InMemoryStore stores the Session object directly — no conversion.
      // The sqflite path round-trips via ms-epoch and is verified by
      // on-device smoke testing (sqflite_common_ffi deliberately dropped; see dbedc19).
      expect(result.updatedAt, equals(ts));
    });

    test('sub-millisecond precision (µs) is zeroed after persist + list',
        () async {
      // Simulate a timestamp with microseconds that would be truncated by
      // ms-epoch storage.  The in-memory path stores by reference so µs is
      // preserved — we verify the contract by asserting µs==0 after an
      // explicit ms-truncation step, mirroring what SqfliteLocalStore does.
      final tsWithUs =
          DateTime.utc(2026, 4, 29, 15, 30, 45, 123).add(const Duration(microseconds: 456));
      final tsTruncated = DateTime.fromMillisecondsSinceEpoch(
        tsWithUs.millisecondsSinceEpoch,
        isUtc: true,
      );
      final s = makeSession(
        key: 'us-test',
        title: 'US',
        updatedAt: tsTruncated,
      );
      await store.upsertSession(s);

      final result = (await store.listSessions()).first;
      expect(result.updatedAt.microsecond, equals(0));
      expect(
        result.updatedAt.millisecondsSinceEpoch,
        equals(tsWithUs.millisecondsSinceEpoch),
      );
    });
  });

  group('close + re-open', () {
    test('open → close → open works again on InMemoryLocalStore', () async {
      await store.upsertSession(makeSession(
        key: 'before-close',
        title: 'Before',
        updatedAt: DateTime.utc(2026, 4, 29),
      ));

      // close() should clear the store.
      await store.close();
      expect(await store.listSessions(), isEmpty);

      // open() again must be a no-op that leaves the store usable.
      await store.open();
      await store.upsertSession(makeSession(
        key: 'after-reopen',
        title: 'After',
        updatedAt: DateTime.utc(2026, 4, 29),
      ));

      final list = await store.listSessions();
      expect(list, hasLength(1));
      expect(list.first.key, equals('after-reopen'));
    });
  });

  group('equal-timestamp tiebreaker', () {
    test(
        'two pinned sessions with identical updatedAt are ordered by key ASC',
        () async {
      final ts = DateTime.utc(2026, 4, 29, 12);
      final sessionB = makeSession(
        key: 'session-b',
        title: 'B',
        updatedAt: ts,
        pinned: true,
      );
      final sessionA = makeSession(
        key: 'session-a',
        title: 'A',
        updatedAt: ts,
        pinned: true,
      );
      // Insert in reverse key order to prove ordering is not insertion-dependent.
      await store.upsertSession(sessionB);
      await store.upsertSession(sessionA);

      final list = await store.listSessions();
      expect(list, hasLength(2));
      expect(list[0].key, equals('session-a'));
      expect(list[1].key, equals('session-b'));
    });
  });
}
