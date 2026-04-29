import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/ui/onboarding/pair_form_screen.dart';
import 'package:stt_tts/ui/widgets/oc_button.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: ocBackgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      colors: [OcColors.accent, OcColors.accent2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Color(0x736CB0FF), blurRadius: 26),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      '⌘',
                      style: TextStyle(
                        fontSize: 38,
                        color: OcColors.bgBottom,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'OpenClaw',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: OcColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Connect to your OpenClaw to start.',
                  style: TextStyle(
                    color: OcColors.textSubtitle,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(flex: 3),
                OcButton(
                  label: 'Connect to my OpenClaw',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PairFormScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
