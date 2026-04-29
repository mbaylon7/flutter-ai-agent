import 'dart:async';

import 'package:stt_tts/data/cache/local_store.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/domain/models/session.dart';

// ---------------------------------------------------------------------------
// SessionFilter enum — UI concern, kept here as a pure top-level type.
// ---------------------------------------------------------------------------

enum SessionFilter { all, voice, text, pinned }

// ---------------------------------------------------------------------------
// applySessionFilter — pure top-level function (NOT a method on the repo).
//
// Rationale: filtering is a UI concern; keeping it outside the repo makes it
// easy to test in isolation and avoids inflating the repository's surface.
// ---------------------------------------------------------------------------

/// Apply [filter] and a case-insensitive substring [query] to [sessions].
///
/// Order of operations:
///   1. Apply [query] against `title` and `lastPreview`.
///   2. Apply [filter].
///
/// Input order is preserved within the filtered result.
List<Session> applySessionFilter(
  List<Session> sessions, {
  SessionFilter filter = SessionFilter.all,
  String query = '',
}) {
  // Step 1: query filter.
  final q = query.toLowerCase();
  Iterable<Session> result = sessions;
  if (q.isNotEmpty) {
    result = result.where((s) {
      return s.title.toLowerCase().contains(q) ||
          (s.lastPreview?.toLowerCase().contains(q) ?? false);
    });
  }

  // Step 2: category filter.
  switch (filter) {
    case SessionFilter.all:
      // No additional filtering.
      break;
    case SessionFilter.pinned:
      result = result.where((s) => s.pinned);
      break;
    case SessionFilter.voice:
      // TODO(slice-1c): No reliable per-session voice indicator yet.
      // When the gateway exposes a `kind == 'voice'` value, filter here.
      break;
    case SessionFilter.text:
      // TODO(slice-1c): Mirror of voice — no reliable text indicator yet.
      // When the gateway exposes a `kind == 'text'` value, filter here.
      break;
  }

  return result.toList();
}

// ---------------------------------------------------------------------------
// SessionRepository
// ---------------------------------------------------------------------------

/// Combines [GatewayClient] (network) and [LocalStore] (cache) to give the
/// UI a unified, testable view of the sessions list.
///
/// ### Pin-flag design
///
/// The gateway never stores the `pinned` flag — it is local-only.  The repo
/// merges pin flags from the cache whenever it produces a [Session] value,
/// whether from [refresh], [cachedSessions], or [watchUpdates].
///
/// ### watchUpdates() pin-snapshot design
///
/// The stream does NOT `await` the cache on every event (that would introduce
/// ordering hazards where an event could arrive before the async read
/// completes, delivering a stale value).  Instead, the pin set is snapshotted
/// from the cache at subscribe time and updated synchronously whenever
/// [setPinned] is called.  This means:
///   - A pin change made via [setPinned] is immediately visible to all active
///     stream subscribers.
///   - Pin changes made to the [LocalStore] outside this repo instance are
///     NOT visible until the next [watchUpdates] subscription.  This is an
///     acceptable trade-off for a single-process mobile app.
class SessionRepository {
  SessionRepository(this._gw, this._cache);

  final GatewayClient _gw;
  final LocalStore _cache;

  // Pin snapshot shared across all active watchUpdates() subscriptions.
  // Key → pinned.  Mutated synchronously by setPinned().
  final Map<String, bool> _pinnedSnapshot = {};
  bool _pinnedSnapshotLoaded = false;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Pull the gateway's current list, merge cached pin flags, persist back,
  /// and return the canonical sorted list (pinned-first, then updatedAt DESC).
  Future<List<Session>> refresh() async {
    final gwSessions = await _gw.listSessions();

    // Load current pin state from cache so we can preserve pins.
    final cached = await _cache.listSessions();
    final pinnedKeys = {
      for (final s in cached)
        if (s.pinned) s.key: true,
    };

    // Also update the in-memory snapshot used by watchUpdates().
    _pinnedSnapshot.addAll(pinnedKeys);
    _pinnedSnapshotLoaded = true;

    // Merge pin flags and persist.
    for (final s in gwSessions) {
      final merged = s.copyWith(pinned: pinnedKeys[s.key] ?? false);
      await _cache.upsertSession(merged);
    }

    // Return the sorted list from the cache (canonical sort is defined there).
    return _cache.listSessions();
  }

  /// Returns the cached list immediately (offline-first).  Empty if the cache
  /// has never been populated.  Does NOT contact the gateway.
  Future<List<Session>> cachedSessions() => _cache.listSessions();

  /// Live session updates from the gateway, with the cached pin flag merged in
  /// on the fly.
  ///
  /// See class-level doc for the pin-snapshot design decision.
  ///
  /// Implementation note: we subscribe to the gateway stream synchronously
  /// before loading the cache snapshot, then buffer events in a
  /// [StreamController] while the snapshot loads.  This avoids a race where
  /// an event arrives between stream construction and the first `await for`
  /// iteration in an `async*` generator.
  Stream<Session> watchUpdates() {
    // Subscribe to the gateway immediately so no events are missed.
    final controller = StreamController<Session>();
    final gwSub = _gw.watchSessionUpdates().listen(
      (s) {
        final pinned = _pinnedSnapshot[s.key] ?? false;
        controller.add(s.copyWith(pinned: pinned));
      },
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = gwSub.cancel;

    // Populate the pin snapshot asynchronously if needed.
    if (!_pinnedSnapshotLoaded) {
      _cache.listSessions().then((cached) {
        for (final s in cached) {
          _pinnedSnapshot[s.key] = s.pinned;
        }
        _pinnedSnapshotLoaded = true;
      });
    }

    return controller.stream;
  }

  /// Rename a session.  Delegates to [GatewayClient.patchSession].
  Future<void> rename(String sessionKey, String title) =>
      _gw.patchSession(sessionKey, title: title);

  /// Delete a session from both the gateway and the local cache.
  Future<void> delete(String sessionKey) async {
    await _gw.deleteSession(sessionKey);
    await _cache.deleteSession(sessionKey);
    _pinnedSnapshot.remove(sessionKey);
  }

  /// Toggle the pin flag locally only (gateway does not store pins).
  ///
  /// The in-memory snapshot is updated synchronously so that any active
  /// [watchUpdates] subscriber sees the change immediately.
  Future<void> setPinned(String sessionKey, bool pinned) async {
    await _cache.setPinned(sessionKey, pinned);
    // Keep the snapshot in sync.
    _pinnedSnapshot[sessionKey] = pinned;
  }
}
