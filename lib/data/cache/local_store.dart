import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:stt_tts/domain/models/session.dart';

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Local cache for the sessions list.
///
/// The repo layer depends only on this abstract type; concrete implementations
/// differ only in persistence mechanism (sqflite vs. in-memory map).
abstract class LocalStore {
  /// Opens / initialises the store. Must be called before any other method.
  /// For [InMemoryLocalStore] this is a no-op.
  Future<void> open();

  /// Insert or fully replace a session (keyed by [Session.key]).
  Future<void> upsertSession(Session s);

  /// Returns all sessions, sorted: pinned first, then by [Session.updatedAt] DESC.
  /// Within each group (pinned / unpinned) the secondary sort is also updatedAt DESC.
  Future<List<Session>> listSessions();

  /// Flip the [Session.pinned] flag without touching any other field.
  /// No-op if the key does not exist.
  Future<void> setPinned(String sessionKey, bool pinned);

  /// Remove a session. No-op if the key does not exist.
  Future<void> deleteSession(String sessionKey);

  /// Remove every session from the store.
  Future<void> clear();
}

// ---------------------------------------------------------------------------
// SqfliteLocalStore — production path
// ---------------------------------------------------------------------------

const _kDbName = 'openclaw_cache.db';
const _kTableSessions = 'sessions';
const _kVersion = 1;

class SqfliteLocalStore extends LocalStore {
  Database? _db;

  @override
  Future<void> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _kDbName);
    _db = await openDatabase(
      path,
      version: _kVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_kTableSessions(
        key              TEXT    PRIMARY KEY,
        title            TEXT    NOT NULL,
        updatedAt        INTEGER NOT NULL,
        kind             TEXT    NOT NULL,
        pinned           INTEGER NOT NULL DEFAULT 0,
        preview          TEXT,
        totalTokens      INTEGER,
        estimatedCostUsd REAL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_sessions_updated ON $_kTableSessions(updatedAt DESC)',
    );
  }

  Database get _requireDb {
    final db = _db;
    if (db == null) throw StateError('SqfliteLocalStore.open() not called');
    return db;
  }

  @override
  Future<void> upsertSession(Session s) async {
    await _requireDb.insert(
      _kTableSessions,
      _toRow(s),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<Session>> listSessions() async {
    final rows = await _requireDb.query(
      _kTableSessions,
      // Sort: pinned DESC (1 before 0), then updatedAt DESC.
      orderBy: 'pinned DESC, updatedAt DESC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> setPinned(String sessionKey, bool pinned) async {
    await _requireDb.update(
      _kTableSessions,
      {'pinned': pinned ? 1 : 0},
      where: 'key = ?',
      whereArgs: [sessionKey],
    );
  }

  @override
  Future<void> deleteSession(String sessionKey) async {
    await _requireDb.delete(
      _kTableSessions,
      where: 'key = ?',
      whereArgs: [sessionKey],
    );
  }

  @override
  Future<void> clear() async {
    await _requireDb.delete(_kTableSessions);
  }

  // -------------------------------------------------------------------------
  // Row <-> Session helpers
  // -------------------------------------------------------------------------

  static Map<String, Object?> _toRow(Session s) => {
        'key': s.key,
        'title': s.title,
        'updatedAt': s.updatedAt.millisecondsSinceEpoch,
        'kind': s.kind,
        'pinned': s.pinned ? 1 : 0,
        'preview': s.lastPreview,
        'totalTokens': s.totalTokens,
        'estimatedCostUsd': s.estimatedCostUsd,
      };

  static Session _fromRow(Map<String, Object?> row) => Session(
        key: row['key'] as String,
        title: row['title'] as String,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['updatedAt'] as int),
          isUtc: true,
        ),
        kind: row['kind'] as String,
        pinned: (row['pinned'] as int) != 0,
        lastPreview: row['preview'] as String?,
        totalTokens: row['totalTokens'] as int?,
        estimatedCostUsd: row['estimatedCostUsd'] as double?,
      );
}

// ---------------------------------------------------------------------------
// InMemoryLocalStore — test / dev path
// ---------------------------------------------------------------------------

/// Pure-Dart in-memory implementation. Suitable for unit tests and
/// Flutter widget tests where sqflite cannot be initialised.
class InMemoryLocalStore extends LocalStore {
  final Map<String, Session> _store = {};

  @override
  Future<void> open() async {
    // No-op for in-memory store.
  }

  @override
  Future<void> upsertSession(Session s) async {
    _store[s.key] = s;
  }

  @override
  Future<List<Session>> listSessions() async {
    final sessions = _store.values.toList()
      ..sort((a, b) {
        // Pinned first: pinned=true (1) > pinned=false (0), so invert comparison.
        final pinnedCmp = (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0);
        if (pinnedCmp != 0) return pinnedCmp;
        // Within each group: newer first.
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return sessions;
  }

  @override
  Future<void> setPinned(String sessionKey, bool pinned) async {
    final existing = _store[sessionKey];
    if (existing == null) return; // no-op
    _store[sessionKey] = existing.copyWith(pinned: pinned);
  }

  @override
  Future<void> deleteSession(String sessionKey) async {
    _store.remove(sessionKey);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}
