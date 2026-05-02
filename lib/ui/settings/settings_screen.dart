import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/ui/settings/about_section.dart';
import 'package:stt_tts/ui/settings/personality_section.dart';
import 'package:stt_tts/ui/settings/privacy_section.dart';
import 'package:stt_tts/ui/settings/voice_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: OcColors.bgBottom,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Settings'),
        foregroundColor: OcColors.textPrimary,
      ),
      body: ListView(
        children: const [
          _SectionLabel('Voice & speech'),
          VoiceSection(),
          _SectionLabel('Personality'),
          PersonalitySection(),
          _SectionLabel('Privacy & data'),
          PrivacySection(),
          _SectionLabel('Help & About'),
          AboutSection(),
          SizedBox(height: 22),
          Center(
            child: Text('OpenClaw · A private AI assistant',
                style: TextStyle(color: OcColors.textMeta, fontSize: 10)),
          ),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: OcColors.textMeta,
            fontWeight: FontWeight.w700,
            fontSize: 10,
            letterSpacing: 0.7,
          ),
        ),
      );
}
