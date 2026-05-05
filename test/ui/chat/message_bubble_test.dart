import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/ui/chat/message_bubble.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Message _message({
  Role role = Role.user,
  String text = 'Hello',
  StreamingState streaming = StreamingState.finalized,
  String? runId,
}) {
  return Message(
    role: role,
    parts: text.isEmpty ? const [] : [TextPart(text)],
    createdAt: DateTime(2024),
    streaming: streaming,
    runId: runId,
  );
}

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: ocLightTheme(),
        home: Scaffold(body: child),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('MessageBubble', () {
    testWidgets('1. user bubble shows text and is right-aligned',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          MessageBubble(
            message: _message(role: Role.user, text: 'Hey there'),
            isLastAssistant: false,
          ),
        ),
      );

      expect(find.text('Hey there'), findsOneWidget);

      // The Align widget carrying the sentinel key should be centerRight.
      final align = tester.widget<Align>(
        find.byKey(const Key('bubble_align_user')),
      );
      expect(align.alignment, Alignment.centerRight);
    });

    testWidgets('2. assistant bubble shows text and is left-aligned',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          MessageBubble(
            message: _message(role: Role.assistant, text: 'Hi back'),
            isLastAssistant: false,
          ),
        ),
      );

      expect(find.text('Hi back'), findsOneWidget);

      final align = tester.widget<Align>(
        find.byKey(const Key('bubble_align_assistant')),
      );
      expect(align.alignment, Alignment.centerLeft);
    });

    testWidgets('3. streaming partial bubble renders animated dots widget',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          MessageBubble(
            message: _message(
              role: Role.assistant,
              text: 'Thinking…',
              streaming: StreamingState.partial,
            ),
            isLastAssistant: false,
          ),
        ),
      );

      // _StreamingDots is identified by its Key.
      expect(find.byKey(const Key('streaming_dots')), findsOneWidget);
    });

    testWidgets('4. failed bubble shows warning indicator', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MessageBubble(
            message: _message(
              role: Role.assistant,
              text: 'Partial answer',
              streaming: StreamingState.failed,
            ),
            isLastAssistant: false,
          ),
        ),
      );

      // The failed chip has Key('failed_chip').
      expect(find.byKey(const Key('failed_chip')), findsOneWidget);
      // The warning icon is present.
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });
}
