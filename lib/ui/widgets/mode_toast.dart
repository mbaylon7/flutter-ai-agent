import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/design_tokens.dart';
import 'package:stt_tts/state/theme_provider.dart';

/// Slides up + fades, 1.5 s total. Pinned at `bottom: 132` (matches
/// `.toast` rule in the design HTML).
void showModeToast(
  BuildContext context,
  String text, {
  Duration duration = const Duration(milliseconds: 1500),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ModeToast(
      text: text,
      duration: duration,
      onDismissed: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _ModeToast extends ConsumerStatefulWidget {
  const _ModeToast({
    required this.text,
    required this.duration,
    required this.onDismissed,
  });

  final String text;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  ConsumerState<_ModeToast> createState() => _ModeToastState();
}

class _ModeToastState extends ConsumerState<_ModeToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);

    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 18,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 62),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
    ]).animate(_ctrl);

    _offset = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween(begin: const Offset(0, 0.6), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem(tween: ConstantTween(Offset.zero), weight: 82),
    ]).animate(_ctrl);

    _ctrl.forward().whenComplete(widget.onDismissed);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(tokensProvider);
    return Positioned(
      left: 0,
      right: 0,
      bottom: OcLayout.toastBottom,
      child: IgnorePointer(
        child: Center(
          child: SlideTransition(
            position: _offset,
            child: FadeTransition(
              opacity: _opacity,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                  decoration: BoxDecoration(
                    color: tokens.toastBg,
                    border: Border.all(color: tokens.toastBorder, width: 1),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.text,
                    style: TextStyle(
                      color: tokens.toastText,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.005 * 13,
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
