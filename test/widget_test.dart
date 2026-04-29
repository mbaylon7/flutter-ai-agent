import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/app.dart';

void main() {
  testWidgets('OpenClaw boots with welcome screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: OpenClawApp()));
    expect(find.text('OpenClaw'), findsOneWidget);
    expect(find.text('Connect to my OpenClaw'), findsOneWidget);
  });
}
