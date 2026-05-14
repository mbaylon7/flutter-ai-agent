import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

/// Briefly shows a centered-bottom toast that slides up and fades.
///
/// Used by the mic/chat mode-switch button to confirm the new mode.
/// Auto-dismisses after [duration] (default 1.5 s) and is non-interactive.
void showModeToast(
  BuildContext context,
  String text, {
  Duration duration = const Duration(milliseconds: 1500),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _ModeToast(
      text: text,
      duration: duration,
      onDismissed: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _ModeToast extends StatefulWidget {
  const _ModeToast({
    required this.text,
    required this.duration,
    required this.onDismissed,
  });

  final String text;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_ModeToast> createState() => _ModeToastState();
}

class _ModeToastState extends State<_ModeToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    // Phases (fractions of total duration):
    //   0.00 - 0.18  fade-in + slide-up
    //   0.18 - 0.80  hold
    //   0.80 - 1.00  fade-out
    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 18,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 62),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
    ]).animate(_controller);

    _offset = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween(begin: const Offset(0, 0.6), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem(tween: ConstantTween(Offset.zero), weight: 82),
    ]).animate(_controller);

    _controller.forward().whenComplete(widget.onDismissed);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: mq.padding.bottom + 100,
      child: IgnorePointer(
        child: Center(
          child: SlideTransition(
            position: _offset,
            child: FadeTransition(
              opacity: _opacity,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: OcColors.textPrimary.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.text,
                    style: TextStyle(
                      color: OcColors.surface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
