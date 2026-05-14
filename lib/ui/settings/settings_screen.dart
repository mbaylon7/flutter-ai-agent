import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/state/theme_provider.dart';
import 'package:stt_tts/ui/settings/about_section.dart';
import 'package:stt_tts/ui/settings/appearance_section.dart';
import 'package:stt_tts/ui/settings/personality_section.dart';
import 'package:stt_tts/ui/settings/privacy_section.dart';
import 'package:stt_tts/ui/settings/voice_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(tokensProvider);
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('Settings', style: TextStyle(color: tokens.text)),
        foregroundColor: tokens.text,
        iconTheme: IconThemeData(color: tokens.text),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          const _SectionLabel('Voice & speech'),
          const VoiceSection(),
          const _SectionLabel('Appearance'),
          const AppearanceSection(),
          const _SectionLabel('Personality'),
          const PersonalitySection(),
          const _SectionLabel('Privacy & data'),
          const PrivacySection(),
          const _SectionLabel('Help & About'),
          const AboutSection(),
          const SizedBox(height: 22),
          Center(
            child: Text(
              'OpenClaw · A private AI assistant',
              style: TextStyle(color: tokens.textMuted, fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionLabel extends ConsumerWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(tokensProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: tokens.textMuted,
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
          letterSpacing: 0.08 * 11.5,
        ),
      ),
    );
  }
}
