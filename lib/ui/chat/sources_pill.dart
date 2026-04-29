import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

/// A small pill shown under an assistant bubble when the message has tool calls.
///
/// Tapping it opens the SourcesSheet.
class SourcesPill extends StatelessWidget {
  const SourcesPill({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '📎 1 source ▾' : '📎 $count sources ▾';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: OcColors.surface,
          border: Border.all(color: OcColors.borderTint),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: OcColors.textSubtitle,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
