import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/state/messages_provider.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:stt_tts/ui/chat/chat_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Message _msg({
  Role role = Role.user,
  String text = 'Hello',
  StreamingState streaming = StreamingState.finalized,
}) =>
    Message(
      role: role,
      parts: [TextPart(text)],
      createdAt: DateTime(2024),
      streaming: streaming,
    );

/// Builds the app with optional provider overrides.
Widget _buildApp({List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: ocLightTheme(),
        home: const Scaffold(body: ChatScreen()),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ChatScreen', () {
    testWidgets(
        '1. shows "Pick a conversation" when currentSessionProvider == null',
        (tester) async {
      await tester.pumpWidget(_buildApp(
        overrides: [
          currentSessionProvider.overrideWith((_) => null),
        ],
      ));

      await tester.pump();

      expect(find.text('Pick a conversation'), findsOneWidget);
    });

    testWidgets(
        '2. renders both user and assistant bubbles when provider yields 2 messages',
        (tester) async {
      const key = 'agent:main:main';
      final m1 = _msg(role: Role.user, text: 'User message here');
      final m2 = _msg(role: Role.assistant, text: 'Assistant reply here');

      await tester.pumpWidget(_buildApp(
        overrides: [
          currentSessionProvider.overrideWith((_) => key),
          messagesProvider(key).overrideWith(
            (_) => Stream.value([m1, m2]),
          ),
        ],
      ));

      // Let the stream deliver its value.
      await tester.pumpAndSettle();

      expect(find.text('User message here'), findsOneWidget);
      expect(find.text('Assistant reply here'), findsOneWidget);
    });

    testWidgets('3. send button is disabled when text field is empty',
        (tester) async {
      const key = 'agent:main:main';

      await tester.pumpWidget(_buildApp(
        overrides: [
          currentSessionProvider.overrideWith((_) => key),
          messagesProvider(key).overrideWith(
            (_) => Stream.value(const []),
          ),
        ],
      ));

      await tester.pumpAndSettle();

      // The send IconButton should be disabled (onPressed == null) when the
      // text field is empty.
      final sendBtn = tester.widget<IconButton>(
        find.byKey(const Key('composer_send_button')),
      );
      expect(sendBtn.onPressed, isNull);
    });
  });
}
