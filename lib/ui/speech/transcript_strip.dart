import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

/// Renders either: live partial transcript (listening) or karaoke subtitle (responding).
class TranscriptStrip extends StatelessWidget {
  const TranscriptStrip({super.key, required this.text, this.highlightStart, this.highlightEnd});
  final String text;
  final int? highlightStart;
  final int? highlightEnd;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox(height: 28);
    if (highlightStart == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: OcColors.textBody, fontSize: 13)),
      );
    }
    final s = highlightStart!.clamp(0, text.length);
    final e = (highlightEnd ?? s).clamp(s, text.length);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: OcColors.textBody),
          children: [
            TextSpan(text: text.substring(0, s), style: const TextStyle(color: OcColors.accent)),
            TextSpan(
              text: text.substring(s, e),
              style: TextStyle(
                color: OcColors.textPrimary,
                backgroundColor: OcColors.accent.withValues(alpha: 0.25),
              ),
            ),
            TextSpan(text: text.substring(e), style: const TextStyle(color: OcColors.textMeta)),
          ],
        ),
      ),
    );
  }
}
