import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/ui/sessions/session_row.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Session _session({
  String key = 's1',
  String title = 'Test session',
  String kind = 'direct',
  bool pinned = false,
  String? lastPreview,
  DateTime? updatedAt,
}) {
  return Session(
    key: key,
    title: title,
    updatedAt: updatedAt ?? DateTime.now().subtract(const Duration(hours: 2)),
    kind: kind,
    pinned: pinned,
    lastPreview: lastPreview,
  );
}

Widget _wrap(Widget child) => MaterialApp(
      theme: ocLightTheme(),
      home: Scaffold(body: child),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SessionRow', () {
    testWidgets('renders title and preview', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SessionRow(
            session: _session(
              title: 'Hello world',
              lastPreview: 'This is a preview',
            ),
            active: false,
            onTap: () {},
            onLongPress: () {},
          ),
        ),
      );

      expect(find.text('Hello world'), findsOneWidget);
      expect(find.text('This is a preview'), findsOneWidget);
    });

    testWidgets('active state shows accent left border via sentinel Key',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          SessionRow(
            session: _session(),
            active: true,
            onTap: () {},
            onLongPress: () {},
          ),
        ),
      );

      // The active Container carries Key('session_row_active').
      final sentinel = find.byKey(const Key('session_row_active'));
      expect(sentinel, findsOneWidget);

      final container = tester.widget<Container>(sentinel);
      final decoration = container.decoration as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.left.color, OcColors.accent);
      expect(border.left.width, 2.0);
    });

    testWidgets('inactive state does not show accent border', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SessionRow(
            session: _session(),
            active: false,
            onTap: () {},
            onLongPress: () {},
          ),
        ),
      );

      expect(find.byKey(const Key('session_row_active')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // formatSessionTime unit tests
  // -------------------------------------------------------------------------

  group('formatSessionTime', () {
    late DateTime now;

    setUp(() {
      now = DateTime(2024, 6, 15, 10, 30); // Saturday 10:30 AM
    });

    test('returns "now" for 5 minutes ago', () {
      final dt = now.subtract(const Duration(minutes: 5));
      expect(formatSessionTime(dt, now), 'now');
    });

    test('returns "now" for 59 minutes ago', () {
      final dt = now.subtract(const Duration(minutes: 59));
      expect(formatSessionTime(dt, now), 'now');
    });

    test('returns time string for earlier today (same day, >1h ago)', () {
      final dt = now.subtract(const Duration(hours: 3)); // 7:30 AM same day
      final result = formatSessionTime(dt, now);
      // Should be a time like "7:30 AM"
      expect(result, contains('AM'));
    });

    test('returns "Yesterday" for yesterday', () {
      final yesterday = now.subtract(const Duration(days: 1));
      expect(formatSessionTime(yesterday, now), 'Yesterday');
    });

    test('returns weekday abbreviation for within 7 days', () {
      final threeDaysAgo = now.subtract(const Duration(days: 3)); // Wednesday
      final result = formatSessionTime(threeDaysAgo, now);
      // Should be a short weekday name
      expect(result.length, lessThanOrEqualTo(3));
      expect(result, isNot('Yesterday'));
      expect(result, isNot('now'));
    });

    test('returns "MMM d" format for 30 days ago (same year)', () {
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final result = formatSessionTime(thirtyDaysAgo, now);
      expect(result, 'May 16');
    });

    test('returns "MMM d, y" for a different year', () {
      final old = DateTime(2022, 3, 5, 9, 0);
      final result = formatSessionTime(old, now);
      expect(result, 'Mar 5, 2022');
    });
  });
}
