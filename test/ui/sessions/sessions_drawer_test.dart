import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/domain/repositories/session_repository.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:stt_tts/ui/sessions/sessions_drawer.dart';

// ---------------------------------------------------------------------------
// Stub SessionsController that bypasses gateway/cache entirely.
// ---------------------------------------------------------------------------

class _StubSessionsController extends SessionsController {
  _StubSessionsController(this._initial);

  final SessionsState _initial;

  @override
  SessionsState build() => _initial;

  // Override _bootstrap to no-op — no gateway, no cache.
  @override
  Future<void> refresh() async {}
}

// ---------------------------------------------------------------------------
// Helper to build a SessionsState pre-populated with sessions.
// ---------------------------------------------------------------------------

SessionsState _dataState(List<Session> sessions) => SessionsState(
      sessions: AsyncValue.data(sessions),
      filter: SessionFilter.all,
      query: '',
    );

const SessionsState _loadingState = SessionsState(
  sessions: AsyncValue.loading(),
  filter: SessionFilter.all,
  query: '',
);

// ---------------------------------------------------------------------------
// Session factory
// ---------------------------------------------------------------------------

Session _session({
  required String key,
  required String title,
  bool pinned = false,
}) =>
    Session(
      key: key,
      title: title,
      updatedAt: DateTime(2024, 1, 1),
      kind: 'direct',
      pinned: pinned,
      lastPreview: 'preview for $title',
    );

// ---------------------------------------------------------------------------
// Widget wrapper
// ---------------------------------------------------------------------------

Widget _buildApp({
  required SessionsState initialState,
  List<Override> extra = const [],
}) {
  return ProviderScope(
    overrides: [
      sessionsProvider.overrideWith(() => _StubSessionsController(initialState)),
      ...extra,
    ],
    child: MaterialApp(
      theme: ocLightTheme(),
      home: const Scaffold(body: SessionsDrawer()),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SessionsDrawer — loading state', () {
    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      await tester.pumpWidget(_buildApp(initialState: _loadingState));

      // Single pump to get the first frame (loading state).
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('SessionsDrawer — data state', () {
    testWidgets(
        'shows "📌 Pinned" group label and both rows for one pinned + one unpinned',
        (tester) async {
      final sessions = [
        _session(key: 'p1', title: 'Pinned session', pinned: true),
        _session(key: 'r1', title: 'Recent session', pinned: false),
      ];

      await tester.pumpWidget(
        _buildApp(initialState: _dataState(sessions)),
      );

      await tester.pumpAndSettle();

      // The "📌 Pinned" section header should appear.
      expect(find.textContaining('Pinned'), findsWidgets);

      // Both session titles should be visible.
      expect(find.text('Pinned session'), findsOneWidget);
      expect(find.text('Recent session'), findsOneWidget);
    });

    testWidgets('tapping a row sets currentSessionProvider', (tester) async {
      final sessions = [_session(key: 'tap_me', title: 'Tap target')];

      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionsProvider.overrideWith(
              () => _StubSessionsController(_dataState(sessions)),
            ),
          ],
          child: MaterialApp(
            theme: ocLightTheme(),
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const Scaffold(body: SessionsDrawer());
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Tap target'), findsOneWidget);

      await tester.tap(find.text('Tap target'));
      await tester.pumpAndSettle();

      expect(capturedRef.read(currentSessionProvider), 'tap_me');
    });
  });

  group('SessionActionsSheet — smoke test', () {
    testWidgets('actions sheet builds without throwing', (tester) async {
      final session = _session(key: 'a1', title: 'Action session');

      await tester.pumpWidget(
        _buildApp(initialState: _dataState([session])),
      );

      await tester.pumpAndSettle();

      // Long-press the session row to open the actions sheet.
      await tester.longPress(find.text('Action session'));
      await tester.pumpAndSettle();

      // Verify the sheet appeared with at least Rename and Delete options.
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });
}
