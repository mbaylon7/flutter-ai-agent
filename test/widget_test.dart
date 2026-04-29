import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/app.dart';
import 'package:stt_tts/data/cache/local_store.dart';
import 'package:stt_tts/data/secure/secure_store.dart';
import 'package:stt_tts/state/connection_provider.dart';
import 'package:stt_tts/state/repositories_provider.dart';

void main() {
  testWidgets('OpenClaw boots with welcome screen', (tester) async {
    // Use fakes so no platform channels are hit and auto-reconnect resolves to
    // data(false) → WelcomeScreen (no stored deviceToken in FakeSecureStore).
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(InMemoryLocalStore()),
          secureStoreProvider.overrideWithValue(FakeSecureStore()),
        ],
        child: const OpenClawApp(),
      ),
    );

    // Pump past the loading frame — FakeSecureStore returns instantly, so one
    // additional pump is enough for the async gap.
    await tester.pump();

    expect(find.text('OpenClaw'), findsOneWidget);
    expect(find.text('Connect to my OpenClaw'), findsOneWidget);
  });
}
