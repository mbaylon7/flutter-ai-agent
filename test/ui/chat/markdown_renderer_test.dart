import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/ui/chat/markdown_renderer.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ocDarkTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('OcMarkdown', () {
    testWidgets('1. plain prose renders without throwing', (tester) async {
      await tester.pumpWidget(
        _wrap(const OcMarkdown('Hello world. This is a paragraph.')),
      );
      await tester.pumpAndSettle();

      // No exception thrown; text should appear.
      expect(find.textContaining('Hello world'), findsOneWidget);
    });

    testWidgets('2. code fence renders HighlightView', (tester) async {
      const code = '```dart\nvoid main() {}\n```';
      await tester.pumpWidget(_wrap(const OcMarkdown(code)));
      await tester.pumpAndSettle();

      expect(find.byType(HighlightView), findsOneWidget);
    });
  });
}
