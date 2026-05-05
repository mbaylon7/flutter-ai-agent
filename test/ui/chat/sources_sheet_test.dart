import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/ui/chat/sources_sheet.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ocLightTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

ToolCallPart _call(String id, String name) =>
    ToolCallPart(id: id, name: name, arguments: const {});

Message _result({
  required String callId,
  String text = 'Result text',
  bool isError = false,
}) =>
    Message(
      role: Role.toolResult,
      parts: [TextPart(text)],
      createdAt: DateTime(2024),
      streaming: StreamingState.finalized,
      toolCallId: callId,
      isError: isError,
    );

void main() {
  group('SourcesSheet', () {
    testWidgets('1. renders one row per ToolCallPart', (tester) async {
      final calls = [
        _call('a', 'web_search'),
        _call('b', 'read_file'),
        _call('c', 'bash'),
      ];
      await tester.pumpWidget(
        _wrap(
          SourcesSheet(
            calls: calls,
            resultsByCallId: const {},
          ),
        ),
      );

      expect(find.text('Searched the web'), findsOneWidget);
      expect(find.text('Read a file'), findsOneWidget);
      expect(find.text('Ran a command'), findsOneWidget);
    });

    testWidgets('2. row with paired result shows snippet', (tester) async {
      final call = _call('x', 'web_search');
      final result = _result(callId: 'x', text: 'Hello from the web');
      await tester.pumpWidget(
        _wrap(
          SourcesSheet(
            calls: [call],
            resultsByCallId: {'x': result},
          ),
        ),
      );

      expect(find.textContaining('Hello from the web'), findsOneWidget);
    });

    testWidgets('3. failed result row is dimmed (Opacity 0.6)', (tester) async {
      final call = _call('y', 'bash');
      final result = _result(callId: 'y', isError: true);
      await tester.pumpWidget(
        _wrap(
          SourcesSheet(
            calls: [call],
            resultsByCallId: {'y': result},
          ),
        ),
      );

      // Find an Opacity widget wrapping the failed row.
      final opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
      final dimmed = opacityWidgets.any((o) => o.opacity == 0.6);
      expect(dimmed, isTrue);
    });
  });
}
