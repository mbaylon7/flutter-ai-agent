import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/voice_provider.dart';

class StateRing extends StatefulWidget {
  const StateRing({super.key, required this.state, required this.level, required this.onTap});
  final VoiceState state;
  final double level;
  final VoidCallback onTap;
  @override
  State<StateRing> createState() => _S();
}

class _S extends State<StateRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final pulse = _c.value; // 0..1
          final isListen = widget.state == VoiceState.listening;
          final isSpeak = widget.state == VoiceState.responding;
          final isThink = widget.state == VoiceState.processing;
          final scale = isListen ? 1.0 + (widget.level * 0.12) + (pulse * 0.04) : 1.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: isThink
                        ? Border.all(
                            color: OcColors.accent.withValues(alpha: 0.5),
                            width: 2,
                            style: BorderStyle.solid, // dash effect mimicked via opacity oscillation
                          )
                        : Border.all(
                            color: isListen || isSpeak
                                ? OcColors.accent.withValues(alpha: 0.85)
                                : OcColors.accent.withValues(alpha: 0.4),
                            width: isListen || isSpeak ? 3 : 2,
                          ),
                    boxShadow: (isListen || isSpeak)
                        ? const [
                            BoxShadow(color: Color(0x8C508CFF), blurRadius: 28),
                          ]
                        : null,
                  ),
                ),
              ),
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSpeak ? OcColors.accent : OcColors.surface,
                  border: Border.all(color: OcColors.accent.withValues(alpha: 0.5)),
                ),
                child: Icon(
                  isSpeak
                      ? Icons.volume_up
                      : isThink
                          ? Icons.more_horiz
                          : Icons.mic,
                  color: isSpeak ? OcColors.bgBottom : OcColors.accent,
                  size: 30,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
