import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:stt_tts/state/ui_mode_provider.dart';
import 'package:stt_tts/state/voice_session.dart';
import 'package:stt_tts/ui/chat/chat_composer.dart';
import 'package:stt_tts/ui/sessions/sessions_drawer.dart';
import 'package:stt_tts/ui/settings/settings_screen.dart';
import 'package:stt_tts/ui/speech/voice_home.dart';
import 'package:stt_tts/ui/widgets/connection_banner.dart';
import 'package:stt_tts/ui/widgets/mode_toast.dart';
import 'package:uuid/uuid.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  bool _initialModeApplied = false;

  String _ensureSession() {
    final key = ref.read(currentSessionProvider);
    if (key != null) return key;
    final fresh = 'agent:main:${const Uuid().v4()}';
    ref.read(currentSessionProvider.notifier).state = fresh;
    return fresh;
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(uiModeProvider);
    final sessionKey = ref.watch(currentSessionProvider);

    if (mode == UiMode.voice && sessionKey == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureSession();
      });
    }

    // First-frame setup: always enable the AI playback hook so every reply is
    // spoken (in chat mode too). Open the mic only if we land in voice mode.
    if (!_initialModeApplied) {
      _initialModeApplied = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final key = _ensureSession();
        final session = ref.read(voiceSessionProvider(key));
        session.enable();
        if (ref.read(uiModeProvider) == UiMode.voice) {
          unawaited(session.startListening());
        }
      });
    }

    // React to mode toggles: STT on/off + toast. AI playback stays bound.
    ref.listen<UiMode>(uiModeProvider, (prev, next) {
      if (prev == next) return;
      final key = _ensureSession();
      final session = ref.read(voiceSessionProvider(key));
      session.enable();
      if (next == UiMode.chat) {
        unawaited(session.stopListening());
        showModeToast(context, 'Chat mode');
      } else {
        unawaited(session.startListening());
        showModeToast(context, 'Voice mode');
      }
    });

    return Scaffold(
      drawer: const Drawer(child: SessionsDrawer()),
      backgroundColor: const Color(0xFF050608),
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            const ConnectionBanner(),
            // Unified body: the voice-style aurora + conversation is shown in
            // BOTH modes. Chat mode just adds a minimal centered text input
            // above the action row.
            Expanded(
              child: sessionKey == null
                  ? const _VoiceEmptyState()
                  : VoiceHome(sessionKey: sessionKey),
            ),
            if (mode == UiMode.chat) const ChatComposer(),
            _ActionBar(mode: mode),
          ],
        ),
      ),
    );
  }
}

/// Shared bottom action row: drawer / mode-switch / settings.
class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.mode});

  final UiMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: 'Conversations',
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(
                Icons.more_vert,
                size: 26,
                color: Colors.white,
              ),
            ),
            _ModeSwitchButton(mode: mode),
            IconButton(
              tooltip: 'Settings',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
              icon: const Icon(
                Icons.settings,
                size: 26,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Center button in the action bar. Tapping flips voice ⇄ chat mode.
/// Icon reflects the current active mode (mic in voice, chat bubble in chat).
class _ModeSwitchButton extends ConsumerWidget {
  const _ModeSwitchButton({required this.mode});

  final UiMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inVoice = mode == UiMode.voice;
    final color = inVoice ? const Color(0xFF3D6BFF) : OcColors.textPrimary;
    return GestureDetector(
      onTap: () {
        ref.read(uiModeProvider.notifier).state =
            inVoice ? UiMode.chat : UiMode.voice;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: anim,
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Icon(
            inVoice ? Icons.mic : Icons.chat_bubble_outline_rounded,
            key: ValueKey<bool>(inVoice),
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }
}

/// One-frame placeholder while a fresh voice-mode session key materialises.
class _VoiceEmptyState extends StatelessWidget {
  const _VoiceEmptyState();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
