import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/state/connection_provider.dart';
import 'package:stt_tts/state/theme_provider.dart';
import 'package:stt_tts/ui/onboarding/welcome_screen.dart';
import 'package:stt_tts/ui/shell/home_shell.dart';

class OpenClawApp extends ConsumerStatefulWidget {
  const OpenClawApp({super.key});

  @override
  ConsumerState<OpenClawApp> createState() => _OpenClawAppState();
}

class _OpenClawAppState extends ConsumerState<OpenClawApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Seed the platform brightness so `tokensProvider` resolves immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final b = MediaQuery.platformBrightnessOf(context);
      ref.read(platformBrightnessProvider.notifier).state = b;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    final b = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    ref.read(platformBrightnessProvider.notifier).state = b;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OpenClaw',
      // We drive colour via OcTokens — the Material theme just needs sane
      // platform defaults (text scaling, ripples, status bar etc.).
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F5F7),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000),
      ),
      themeMode: _materialThemeMode(ref.watch(appThemeProvider)),
      home: const _AppRouter(),
    );
  }
}

ThemeMode _materialThemeMode(AppThemeMode m) {
  switch (m) {
    case AppThemeMode.dark:
      return ThemeMode.dark;
    case AppThemeMode.light:
      return ThemeMode.light;
    case AppThemeMode.system:
      return ThemeMode.system;
  }
}

class _AppRouter extends ConsumerWidget {
  const _AppRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reconnect = ref.watch(autoReconnectControllerProvider);
    final tokens = ref.watch(tokensProvider);

    return reconnect.when(
      loading: () => Scaffold(
        backgroundColor: tokens.bg,
        body: Center(
          child: CircularProgressIndicator(color: tokens.accent),
        ),
      ),
      data: (connected) {
        if (connected) {
          return const HomeShell();
        }
        return const WelcomeScreen();
      },
      error: (e, _) => const WelcomeScreen(),
    );
  }
}
