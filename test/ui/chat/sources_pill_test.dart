import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/ui/chat/sources_pill.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ocDarkTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('SourcesPill', () {
    testWidgets('1a. renders "1 source" for count=1', (tester) async {
      await tester.pumpWidget(
        _wrap(SourcesPill(count: 1, onTap: () {})),
      );
      expect(find.textContaining('1 source'), findsOneWidget);
      expect(find.textContaining('sources'), findsNothing);
    });

    testWidgets('1b. renders "3 sources" for count=3', (tester) async {
      await tester.pumpWidget(
        _wrap(SourcesPill(count: 3, onTap: () {})),
      );
      expect(find.textContaining('3 sources'), findsOneWidget);
    });

    testWidgets('2. tap fires the callback', (tester) async {
      var fired = false;
      await tester.pumpWidget(
        _wrap(SourcesPill(count: 2, onTap: () => fired = true)),
      );
      await tester.tap(find.byType(SourcesPill));
      expect(fired, isTrue);
    });
  });
}
