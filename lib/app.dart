import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/connection_provider.dart';
import 'package:stt_tts/ui/onboarding/welcome_screen.dart';

class OpenClawApp extends ConsumerWidget {
  const OpenClawApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OpenClaw',
      theme: ocDarkTheme(),
      home: const _AppRouter(),
    );
  }
}

class _AppRouter extends ConsumerWidget {
  const _AppRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reconnect = ref.watch(autoReconnectControllerProvider);

    return reconnect.when(
      loading: () => Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: const Center(child: CircularProgressIndicator()),
      ),
      data: (connected) {
        if (connected) {
          // TODO(Task 9): Replace with HomeShell once it is built.
          return Scaffold(
            body: Center(
              child: Text(
                'Connected — HomeShell coming in Task 9',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }
        return const WelcomeScreen();
      },
      error: (e, _) => const WelcomeScreen(),
    );
  }
}
