import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/data/cache/local_store.dart';
import 'package:stt_tts/data/secure/secure_store.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/domain/repositories/session_repository.dart';
import 'package:stt_tts/state/connection_provider.dart';
import 'package:stt_tts/state/repositories_provider.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:stt_tts/ui/shell/home_shell.dart';

// ---------------------------------------------------------------------------
// Stub SessionsController — bypasses gateway/cache.
// ---------------------------------------------------------------------------

class _StubSessionsController extends SessionsController {
  _StubSessionsController(this._initial);
  final SessionsState _initial;

  @override
  SessionsState build() => _initial;

  @override
  Future<void> refresh() async {}
}

SessionsState _dataState(List<Session> sessions) => SessionsState(
      sessions: AsyncValue.data(sessions),
      filter: SessionFilter.all,
      query: '',
    );

const SessionsState _emptyState = SessionsState(
  sessions: AsyncValue.data([]),
  filter: SessionFilter.all,
  query: '',
);

Session _session({required String key, required String title}) => Session(
      key: key,
      title: title,
      updatedAt: DateTime(2024, 1, 1),
      kind: 'direct',
      pinned: false,
      lastPreview: 'preview',
    );

// ---------------------------------------------------------------------------
// Helper to build the shell with minimal overrides.
// FakeSecureStore (no tokens) causes autoReconnectController → data(false),
// which means banner is hidden (not .hasError). Good enough for shell tests.
// ---------------------------------------------------------------------------

Widget _buildShell({
  required SessionsState sessionsState,
  String? initialSessionKey,
}) {
  return ProviderScope(
    overrides: [
      localStoreProvider.overrideWithValue(InMemoryLocalStore()),
      secureStoreProvider.overrideWithValue(FakeSecureStore()),
      sessionsProvider.overrideWith(
        () => _StubSessionsController(sessionsState),
      ),
      if (initialSessionKey != null)
        currentSessionProvider.overrideWith((_) => initialSessionKey),
    ],
    child: MaterialApp(
      theme: ocDarkTheme(),
      home: const HomeShell(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('HomeShell', () {
    testWidgets('renders AppBar with title "OpenClaw" when no session selected',
        (tester) async {
      await tester.pumpWidget(
        _buildShell(sessionsState: _emptyState),
      );
      await tester.pumpAndSettle();

      expect(find.text('OpenClaw'), findsOneWidget);
    });

    testWidgets(
        'post-frame callback sets currentSessionProvider to first session key',
        (tester) async {
      final sessions = [
        _session(key: 'first', title: 'First Session'),
        _session(key: 'second', title: 'Second Session'),
      ];

      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStoreProvider.overrideWithValue(InMemoryLocalStore()),
            secureStoreProvider.overrideWithValue(FakeSecureStore()),
            sessionsProvider.overrideWith(
              () => _StubSessionsController(_dataState(sessions)),
            ),
          ],
          child: MaterialApp(
            theme: ocDarkTheme(),
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const HomeShell();
              },
            ),
          ),
        ),
      );

      // First pump — build phase; post-frame callback is scheduled.
      await tester.pump();
      // Second pump — executes the post-frame callback.
      await tester.pump();

      expect(capturedRef.read(currentSessionProvider), 'first');
    });
  });
}
