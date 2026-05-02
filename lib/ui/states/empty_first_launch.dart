import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/ui/widgets/oc_button.dart';

/// Rendered on the home when the user has zero conversations yet.
///
/// - "Hi {name}" greeting + friendly nudge.
/// - Tap-to-talk primary CTA.
/// - "or start typing" secondary link.
class EmptyFirstLaunch extends StatelessWidget {
  const EmptyFirstLaunch({
    super.key,
    required this.userName,
    required this.onTapToTalk,
    required this.onStartTyping,
  });

  final String userName;
  final VoidCallback onTapToTalk;
  final VoidCallback onStartTyping;

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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('👋', style: TextStyle(fontSize: 36)),
                const SizedBox(height: 14),
                Text(
                  'Hi $userName',
                  style: const TextStyle(
                    color: OcColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Your assistant is ready. Tap below and say something — "
                  "or type if you'd rather.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: OcColors.textSubtitle, fontSize: 12),
                ),
                const SizedBox(height: 22),
                OcButton(label: 'Tap to talk', onPressed: onTapToTalk),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: onStartTyping,
                  child: const Text(
                    'or start typing',
                    style: TextStyle(color: OcColors.accent, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
