import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

/// Three-dot animated ellipsis shown between a user bubble and an assistant
/// placeholder while the gateway is "thinking" (ChatStarted received but no
/// delta yet).
class WorkingIndicator extends StatefulWidget {
  const WorkingIndicator({super.key});

  @override
  State<WorkingIndicator> createState() => _WorkingIndicatorState();
}

class _WorkingIndicatorState extends State<WorkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Looking it up',
            style: const TextStyle(
              color: OcColors.textMeta,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 4),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => _ThreeDots(value: _controller.value),
          ),
        ],
      ),
    );
  }
}

class _ThreeDots extends StatelessWidget {
  const _ThreeDots({required this.value});

  /// [0, 1) from the AnimationController.
  final double value;

  @override
  Widget build(BuildContext context) {
    const dotSize = 4.0;
    const dotSpacing = 5.0;
    // Each dot lights up for a 1/3 of the cycle then dims.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        // Phase offset per dot so they animate sequentially.
        final phase = (value - i / 3.0) % 1.0;
        // Bright during [0, 0.33), dim otherwise.
        final bright = phase < 0.33;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: dotSpacing / 2),
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bright ? OcColors.textSubtitle : OcColors.textMeta,
            ),
          ),
        );
      }),
    );
  }
}
