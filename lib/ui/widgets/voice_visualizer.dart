import 'dart:math';
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

/// Wave bars driven by `level` 0..1 (mic level when listening, pulse when speaking).
class VoiceVisualizer extends StatelessWidget {
  const VoiceVisualizer({super.key, required this.level, required this.active});
  final double level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final rng = Random(level.hashCode);
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(24, (i) {
          final base = active ? (level * 0.6) + (rng.nextDouble() * level * 0.4) : 0.08;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 4,
            height: 6 + base * 30,
            decoration: BoxDecoration(
              color: active
                  ? OcColors.accent.withValues(alpha: 0.3 + base * 0.7)
                  : OcColors.borderTint,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}
