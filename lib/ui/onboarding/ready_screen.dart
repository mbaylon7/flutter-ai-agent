import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/ui/widgets/oc_button.dart';

class ReadyScreen extends StatelessWidget {
  const ReadyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: ocBackgroundGradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: OcColors.overlayTint,
                      border: Border.all(color: OcColors.accent, width: 2),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.check,
                        color: OcColors.accent,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    "You're in",
                    style: TextStyle(
                      color: OcColors.textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Connection live. Slice 1B will land the chat UI here.',
                    style: TextStyle(
                      color: OcColors.textSubtitle,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 26),
                  OcButton(label: 'Done for now', onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
