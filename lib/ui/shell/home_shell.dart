import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:stt_tts/ui/sessions/sessions_drawer.dart';
import 'package:stt_tts/ui/settings/settings_screen.dart';
import 'package:stt_tts/ui/speech/voice_home.dart';
import 'package:stt_tts/ui/states/empty_first_launch.dart';
import 'package:stt_tts/ui/widgets/connection_banner.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    // Attempt initial session selection once the widget is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSelectFirst());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // React when the sessions list arrives after initState (e.g. network fetch).
    ref.listenManual(sessionsProvider, (prev, next) {
      _maybeSelectFirst();
    });
  }

  void _maybeSelectFirst() {
    if (!mounted) return;
    final currentKey = ref.read(currentSessionProvider);
    if (currentKey != null) return; // already selected

    final sessions = ref.read(sessionsProvider).sessions.valueOrNull;
    if (sessions != null && sessions.isNotEmpty) {
      ref.read(currentSessionProvider.notifier).state = sessions.first.key;
    }
  }

  String _resolveTitle() {
    final currentKey = ref.watch(currentSessionProvider);
    if (currentKey == null) return 'OpenClaw';

    final sessions =
        ref.watch(sessionsProvider).sessions.valueOrNull ?? const [];
    final session = sessions.cast<dynamic>().firstWhere(
          (s) => s.key == currentKey,
          orElse: () => null,
        );
    if (session == null) return 'Conversation';
    return (session.title as String?) ?? 'Conversation';
  }

  @override
  Widget build(BuildContext context) {
    final title = _resolveTitle();

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Open conversations',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      drawer: const Drawer(child: SessionsDrawer()),
      body: Column(
        children: [
          const ConnectionBanner(),
          Expanded(
            child: Builder(
              builder: (context) {
                final sessionKey = ref.watch(currentSessionProvider);
                if (sessionKey == null) {
                  return EmptyFirstLaunch(
                    userName: 'there',
                    onTapToTalk: () {
                      // Slice 1: starting a new conversation goes through the gateway —
                      // the wiring lands later (creating a session via chat.send is the
                      // simplest path). For now show a hint.
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Starting a new conversation comes in a later slice')),
                      );
                    },
                    onStartTyping: () {
                      // Same idea — chat composer needs a session.
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Starting a new conversation comes in a later slice')),
                      );
                    },
                  );
                }
                return VoiceHome(sessionKey: sessionKey);
              },
            ),
          ),
        ],
      ),
    );
  }
}
