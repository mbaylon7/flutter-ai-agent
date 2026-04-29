import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/domain/repositories/session_repository.dart';
import 'package:stt_tts/state/repositories_provider.dart';

// ---------------------------------------------------------------------------
// SessionsState
// ---------------------------------------------------------------------------

class SessionsState {
  const SessionsState({
    required this.sessions,
    required this.filter,
    required this.query,
  });

  final AsyncValue<List<Session>> sessions;
  final SessionFilter filter;
  final String query;

  /// Filtered + queried view used by the UI.
  AsyncValue<List<Session>> get visible =>
      sessions.whenData((all) => applySessionFilter(all, filter: filter, query: query));

  SessionsState copyWith({
    AsyncValue<List<Session>>? sessions,
    SessionFilter? filter,
    String? query,
  }) =>
      SessionsState(
        sessions: sessions ?? this.sessions,
        filter: filter ?? this.filter,
        query: query ?? this.query,
      );
}

// ---------------------------------------------------------------------------
// SessionsController
// ---------------------------------------------------------------------------

class SessionsController extends Notifier<SessionsState> {
  @override
  SessionsState build() {
    _bootstrap();
    return const SessionsState(
      sessions: AsyncValue.loading(),
      filter: SessionFilter.all,
      query: '',
    );
  }

  Future<void> _bootstrap() async {
    final repo = ref.read(sessionRepositoryProvider);

    // 1) Show cache fast.
    final cached = await repo.cachedSessions();
    if (cached.isNotEmpty) {
      state = state.copyWith(sessions: AsyncValue.data(cached));
    }

    // 2) Refresh from gateway (if connected; if not, leave cached).
    try {
      final fresh = await repo.refresh();
      state = state.copyWith(sessions: AsyncValue.data(fresh));
    } catch (e, st) {
      // Only clobber to error if we don't have cached data.
      if (cached.isEmpty) {
        state = state.copyWith(sessions: AsyncValue.error(e, st));
      }
    }

    // 3) Subscribe to live updates.
    ref.onDispose(
      repo.watchUpdates().listen((s) {
        final list = state.sessions.valueOrNull ?? const <Session>[];
        // Upsert by key, then re-sort by canonical order (pinned-first, updatedAt DESC).
        final next = [...list.where((x) => x.key != s.key), s]
          ..sort((a, b) {
            if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
            return b.updatedAt.compareTo(a.updatedAt);
          });
        state = state.copyWith(sessions: AsyncValue.data(next));
      }).cancel,
    );
  }

  void setFilter(SessionFilter f) => state = state.copyWith(filter: f);

  void setQuery(String q) => state = state.copyWith(query: q);

  Future<void> refresh() async {
    final repo = ref.read(sessionRepositoryProvider);
    try {
      final fresh = await repo.refresh();
      state = state.copyWith(sessions: AsyncValue.data(fresh));
    } catch (e, st) {
      if (state.sessions.valueOrNull?.isEmpty ?? true) {
        state = state.copyWith(sessions: AsyncValue.error(e, st));
      }
    }
  }

  Future<void> setPinned(String key, bool pinned) async {
    await ref.read(sessionRepositoryProvider).setPinned(key, pinned);
    // Optimistic local update.
    final list = state.sessions.valueOrNull ?? const <Session>[];
    final updated = list
        .map((s) => s.key == key ? s.copyWith(pinned: pinned) : s)
        .toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    state = state.copyWith(sessions: AsyncValue.data(updated));
  }

  Future<void> rename(String key, String title) async {
    await ref.read(sessionRepositoryProvider).rename(key, title);
    // The gateway will emit an updated Session via watchUpdates → handled there.
  }

  Future<void> delete(String key) async {
    await ref.read(sessionRepositoryProvider).delete(key);
    final list = state.sessions.valueOrNull ?? const <Session>[];
    state = state.copyWith(
      sessions: AsyncValue.data(list.where((s) => s.key != key).toList()),
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final sessionsProvider =
    NotifierProvider<SessionsController, SessionsState>(SessionsController.new);

/// Convenience derived provider for the UI — returns the filtered+queried view.
final visibleSessionsProvider = Provider<AsyncValue<List<Session>>>(
  (ref) => ref.watch(sessionsProvider).visible,
);

/// Which session is currently open in the chat thread.
/// UI (Task 9) sets this to list.first.key when sessions first load.
final currentSessionProvider = StateProvider<String?>((_) => null);
