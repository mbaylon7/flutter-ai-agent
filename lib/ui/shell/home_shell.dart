import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/design_tokens.dart';
import 'package:stt_tts/state/connection_provider.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:stt_tts/state/theme_provider.dart';
import 'package:stt_tts/state/ui_mode_provider.dart';
import 'package:stt_tts/state/voice_session.dart';
import 'package:stt_tts/ui/chat/chat_composer.dart';
import 'package:stt_tts/ui/sessions/sessions_drawer.dart';
import 'package:stt_tts/ui/settings/settings_screen.dart';
import 'package:stt_tts/ui/speech/voice_home.dart';
import 'package:stt_tts/ui/widgets/agent_required_notice.dart';
import 'package:stt_tts/ui/widgets/mode_toast.dart';
import 'package:uuid/uuid.dart';

/// Home shell — layout matches `design/voice-app.html`:
///
/// * Wave stage fills the bottom 50% behind everything (rendered by
///   [VoiceHome]).
/// * Conversation list overlays from `top: 64` to `bottom: 135`.
/// * Chat-mode minimal input pinned at `bottom: 141`.
/// * Controls row pinned at `bottom: 35` (drawer / mic / settings).
/// * Toast pinned at `bottom: 132` (managed by [showModeToast]).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  bool _initialModeApplied = false;

  /// Whether the "no agent connected" launch notice has fired this app session.
  /// Static so it survives HomeShell remounts (e.g. the router re-rendering) —
  /// the user only needs the early nudge once per launch.
  static bool _agentNoticeShown = false;

  String _ensureSession() {
    final key = ref.read(currentSessionProvider);
    if (key != null) return key;
    final fresh = 'agent:main:${const Uuid().v4()}';
    ref.read(currentSessionProvider.notifier).state = fresh;
    return fresh;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(tokensProvider);
    final mode = ref.watch(uiModeProvider);
    final sessionKey = ref.watch(currentSessionProvider);
    // Edge-to-edge means the controls would render under the gesture/nav bar.
    // Add the system bottom inset to every bottom-pinned widget.
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    if (mode == UiMode.voice && sessionKey == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureSession();
      });
    }

    // First-frame setup: always bind AI playback so every reply is spoken;
    // open the mic only if we land in voice mode.
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
        // Early "no agent" awareness: give the silent reconnect a moment to
        // resolve, then nudge the user to connect if there's still no agent.
        // Fires once per app session (static guard) and is themed for
        // black/white via [showAgentRequiredNotice].
        if (!_agentNoticeShown) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (_agentNoticeShown || !context.mounted) return;
            if (!ref.read(isAgentConnectedProvider)) {
              _agentNoticeShown = true;
              showAgentRequiredNotice(context, ref);
            }
          });
        }
      });
    }

    // React to mode toggles: STT on/off + toast.
    ref.listen<UiMode>(uiModeProvider, (prev, next) {
      if (prev == next) return;
      final key = _ensureSession();
      final session = ref.read(voiceSessionProvider(key));
      session.enable();
      if (next == UiMode.chat) {
        unawaited(session.stopListening());
        showModeToast(context, 'Chat mode');
      } else {
        // Leaving chat mode: collapse the soft keyboard. Composer has the
        // focus while chat mode is active; voice mode should never show a
        // keyboard underneath the wave/controls.
        FocusManager.instance.primaryFocus?.unfocus();
        unawaited(session.startListening());
        showModeToast(context, 'Voice mode');
      }
    });

    // React to session changes (new chat / switching conversations). Only the
    // first-frame setup and mode toggles called startListening() before, so a
    // freshly-created conversation never opened the mic — leaving the wave
    // visualizer idle (no mic level → it sits in its flat "calm" state, which
    // reads as "the animation is missing"). Bind AI playback for the new
    // session and, in voice mode, start listening so the wave comes alive.
    ref.listen<String?>(currentSessionProvider, (prev, next) {
      if (next == null || next == prev) return;
      final session = ref.read(voiceSessionProvider(next));
      session.enable();
      if (ref.read(uiModeProvider) == UiMode.voice) {
        unawaited(session.startListening());
      }
    });

    return Scaffold(
      drawer: const Drawer(child: SessionsDrawer()),
      backgroundColor: tokens.bg,
      body: Stack(
        children: [
          // Wave stage (bottom 50%) + conversation overlay.
          if (sessionKey != null)
            Positioned.fill(child: VoiceHome(sessionKey: sessionKey))
          else
            const SizedBox.expand(),

          // Chat input — pinned 141 px from the bottom, fades in chat mode.
          Positioned(
            left: 0,
            right: 0,
            bottom: OcLayout.chatInputBottom + safeBottom,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: mode == UiMode.chat ? 1 : 0,
              child: IgnorePointer(
                ignoring: mode != UiMode.chat,
                child: const ChatComposer(),
              ),
            ),
          ),

          // Controls — 35 px from bottom, 36 px gap, 76 px mic.
          Positioned(
            left: 0,
            right: 0,
            bottom: OcLayout.controlsBottom + safeBottom,
            child: _Controls(mode: mode),
          ),
        ],
      ),
    );
  }
}

/// Bottom controls row: drawer · mic-mode-switch · settings.
class _Controls extends ConsumerWidget {
  const _Controls({required this.mode});

  final UiMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(tokensProvider);
    final inChat = mode == UiMode.chat;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _IconButton(
          tooltip: 'Conversations',
          icon: _DotsIcon(color: tokens.micIcon),
          onTap: () => Scaffold.of(context).openDrawer(),
        ),
        const SizedBox(width: OcLayout.controlsGap),
        _MicButton(active: !inChat),
        const SizedBox(width: OcLayout.controlsGap),
        _IconButton(
          tooltip: 'Settings',
          icon: _ThinGearIcon(
            size: OcLayout.gearIconSize,
            color: tokens.micIcon,
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        radius: OcLayout.iconBtnSize / 2,
        onTap: onTap,
        child: SizedBox(
          width: OcLayout.iconBtnSize,
          height: OcLayout.iconBtnSize,
          child: Center(child: icon),
        ),
      ),
    );
  }
}

/// Three vertical dots — matches the SVG in the HTML controls row.
class _DotsIcon extends StatelessWidget {
  const _DotsIcon({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: OcLayout.smallIconSize,
      height: OcLayout.smallIconSize,
      child: CustomPaint(painter: _DotsPainter(color: color)),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final r = size.width * (1.4 / 24);
    final paint = Paint()..color = color;
    canvas.drawCircle(Offset(cx, size.height * (5 / 24)), r, paint);
    canvas.drawCircle(Offset(cx, size.height * (12 / 24)), r, paint);
    canvas.drawCircle(Offset(cx, size.height * (19 / 24)), r, paint);
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => old.color != color;
}

/// 76×76 mic / chat-bubble mode-switch button. Active styling when in
/// voice mode; neutral / dimmer when in chat mode (matches `.mode-chat
/// .mic-btn` rule).
class _MicButton extends ConsumerWidget {
  const _MicButton({required this.active});
  final bool active;

  /// Live-mic red used when voice mode is on. Mic is always listening in
  /// voice mode, so this colour reads as a "recording" indicator.
  static const _liveRed = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(tokensProvider);
    // Voice mode: solid red, white glyph, no border (the live-mic style).
    // Chat mode: neutral surface tones from the design tokens.
    final bg = active ? _liveRed : tokens.micBg;
    final iconColor = active ? Colors.white : tokens.micIcon;
    final border = active ? null : Border.all(color: tokens.micBorder, width: 1);

    return GestureDetector(
      onTap: () {
        final current = ref.read(uiModeProvider);
        ref.read(uiModeProvider.notifier).state =
            current == UiMode.voice ? UiMode.chat : UiMode.voice;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        width: OcLayout.micSize,
        height: OcLayout.micSize,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: border,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.65, end: 1).animate(anim),
              child: child,
            ),
          ),
          child: Icon(
            active ? Icons.mic_none_rounded : Icons.chat_bubble_outline_rounded,
            key: ValueKey<bool>(active),
            color: iconColor,
            size: OcLayout.micIconSize,
          ),
        ),
      ),
    );
  }
}

// ─── Thin gear icon ─────────────────────────────────────────────────
//
// Material's `Icons.settings_outlined` is too heavy even at low `weight`,
// so we paint our own: 8 teeth radiating from a central hub, stroked with
// a ~1-px line. Matches the Feather-style gear in the HTML design SVG.

class _ThinGearIcon extends StatelessWidget {
  const _ThinGearIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GearPainter(color: color)),
    );
  }
}

class _GearPainter extends CustomPainter {
  _GearPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * (1.4 / 24)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // Hub circle.
    canvas.drawCircle(Offset(cx, cy), size.width * 0.18, stroke);

    // Outer gear ring with 8 teeth.
    const teeth = 8;
    final outerR = size.width * 0.46;
    final innerR = size.width * 0.36;
    final tooth = (pi * 2) / teeth;
    final tipHalf = tooth * 0.18;
    final baseHalf = tooth * 0.28;

    Offset at(double a, double r) =>
        Offset(cx + r * cos(a), cy + r * sin(a));

    final path = Path();
    for (var i = 0; i < teeth; i++) {
      final c = -pi / 2 + i * tooth; // first tooth at top
      final baseL = c - baseHalf;
      final tipL = c - tipHalf;
      final tipR = c + tipHalf;
      final baseR = c + baseHalf;
      final nextBaseL = -pi / 2 + (i + 1) * tooth - baseHalf;

      if (i == 0) {
        final p = at(baseL, innerR);
        path.moveTo(p.dx, p.dy);
      }

      final pTipL = at(tipL, outerR);
      path.lineTo(pTipL.dx, pTipL.dy);
      final pTipR = at(tipR, outerR);
      path.arcToPoint(pTipR,
          radius: Radius.circular(outerR), clockwise: true, largeArc: false);
      final pBaseR = at(baseR, innerR);
      path.lineTo(pBaseR.dx, pBaseR.dy);
      final pNextBaseL = at(nextBaseL, innerR);
      path.arcToPoint(pNextBaseL,
          radius: Radius.circular(innerR), clockwise: true, largeArc: false);
    }
    path.close();
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _GearPainter old) => old.color != color;
}
