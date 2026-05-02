import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/data/permissions/permissions.dart';
import 'package:stt_tts/ui/widgets/oc_button.dart';

/// Rendered inside VoiceHome when the user has denied (or permanently
/// denied) microphone permission.
class MicDeniedState extends StatelessWidget {
  const MicDeniedState({super.key, required this.onTypeInstead});
  final VoidCallback onTypeInstead;

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
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: OcColors.danger.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mic_off,
                      color: OcColors.danger, size: 32),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Microphone is off',
                  style: TextStyle(
                    color: OcColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'To talk, OpenClaw needs the microphone. '
                  'Open Settings to enable it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: OcColors.textSubtitle, fontSize: 12),
                ),
                const SizedBox(height: 22),
                OcButton(
                  label: 'Open Settings',
                  onPressed: () => MicPermission().openSettings(),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: onTypeInstead,
                  child: const Text(
                    'or type instead',
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
