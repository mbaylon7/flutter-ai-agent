import 'package:flutter_test/flutter_test.dart';

import 'package:stt_tts/main.dart';

void main() {
  testWidgets('renders STT/TTS POC UI', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('STT + TTS Playground'), findsOneWidget);
    expect(find.text('Text to Speech'), findsOneWidget);
    expect(find.text('Speech to Text'), findsOneWidget);
    expect(find.text('Speak Text'), findsOneWidget);
    expect(
      find.text('Phase 2 POC: speech_to_text + flutter_tts'),
      findsOneWidget,
    );
  });
}
