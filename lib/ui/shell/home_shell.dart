import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:stt_tts/state/ui_mode_provider.dart';
import 'package:stt_tts/state/voice_session.dart';
import 'package:stt_tts/ui/chat/chat_screen.dart';
import 'package:stt_tts/ui/sessions/sessions_drawer.dart';
import 'package:stt_tts/ui/speech/voice_home.dart';
import 'package:stt_tts/ui/widgets/connection_banner.dart';
import 'package:uuid/uuid.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  void _ensureSession() {
    final key = ref.read(currentSessionProvider);
    if (key != null) return;
    final fresh = 'agent:main:${const Uuid().v4()}';
    ref.read(currentSessionProvider.notifier).state = fresh;
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(uiModeProvider);
    final sessionKey = ref.watch(currentSessionProvider);

    // Voice mode needs a session key for the StateRing controller. If we land
    // in voice mode without one (cold launch, or after "+ new conversation"),
    // create a fresh one in the next frame so the mic appears immediately.
    if (mode == UiMode.voice && sessionKey == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureSession();
      });
    }

    // When the user toggles voice → chat, fully stop the voice session so
    // the mic and TTS release. Chat mode never auto-plays.
    ref.listen<UiMode>(uiModeProvider, (prev, next) {
      if (prev == UiMode.voice && next == UiMode.chat) {
        final key = ref.read(currentSessionProvider);
        if (key != null) {
          unawaited(ref.read(voiceSessionProvider(key)).stop());
        }
      }
    });

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AppBar(
              backgroundColor: OcColors.surface.withValues(alpha: 0.65),
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: 'Open conversations',
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              title: null,
              centerTitle: false,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _ModeToggle(
                    mode: mode,
                    onChanged: (m) =>
                        ref.read(uiModeProvider.notifier).state = m,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      drawer: const Drawer(child: SessionsDrawer()),
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).padding.top + kToolbarHeight,
          ),
          const ConnectionBanner(),
          Expanded(
            child: mode == UiMode.voice
                ? (sessionKey == null
                    ? const _VoiceEmptyState()
                    : VoiceHome(sessionKey: sessionKey))
                : const ChatScreen(),
          ),
        ],
      ),
    );
  }
}

/// Pill-shaped 2-segment Voice / Chat toggle.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final UiMode mode;
  final ValueChanged<UiMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: OcColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            icon: Icons.graphic_eq_rounded,
            label: 'Voice',
            selected: mode == UiMode.voice,
            onTap: () => onChanged(UiMode.voice),
          ),
          _segment(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Chat',
            selected: mode == UiMode.chat,
            onTap: () => onChanged(UiMode.chat),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? OcColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? OcColors.textPrimary : OcColors.textSubtitle,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color:
                    selected ? OcColors.textPrimary : OcColors.textSubtitle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Brief placeholder shown for the single frame between voice-mode entry and
/// the post-frame callback that materializes a fresh session key.
class _VoiceEmptyState extends StatelessWidget {
  const _VoiceEmptyState();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}
