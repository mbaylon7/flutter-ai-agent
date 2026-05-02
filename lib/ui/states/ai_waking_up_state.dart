import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

/// Rendered while the gateway/agent container is booting up after idle.
///
/// Spinning dashed ring + honest copy: "Usually 10–15 seconds."
class AiWakingUpState extends StatefulWidget {
  const AiWakingUpState({super.key});

  @override
  State<AiWakingUpState> createState() => _AiWakingUpStateState();
}

class _AiWakingUpStateState extends State<AiWakingUpState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [OcColors.bgTop, OcColors.bgBottom],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RotationTransition(
                turns: _c,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: OcColors.accent.withValues(alpha: 0.5),
                      width: 3,
                    ),
                  ),
                  child: const Icon(Icons.settings,
                      color: OcColors.accent, size: 32),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Waking up your assistant',
                style: TextStyle(
                  color: OcColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Usually 10–15 seconds.',
                style: TextStyle(color: OcColors.textSubtitle, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
