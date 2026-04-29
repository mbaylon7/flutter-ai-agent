import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: ocBackgroundGradient),
        child: const SafeArea(
          child: Center(
            child: Text(
              'OpenClaw — slice 1A',
              style: TextStyle(
                color: OcColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
