import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/state/auth_provider.dart';
import 'package:stt_tts/state/onboarding_provider.dart';
import 'package:stt_tts/state/theme_provider.dart';
import 'package:stt_tts/ui/settings/about_section.dart';
import 'package:stt_tts/ui/settings/agent_setup_section.dart';
import 'package:stt_tts/ui/settings/appearance_section.dart';
import 'package:stt_tts/ui/settings/personality_section.dart';
import 'package:stt_tts/ui/settings/privacy_section.dart';
import 'package:stt_tts/ui/settings/voice_section.dart';
import 'package:stt_tts/state/connection_provider.dart';

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
          const _SectionLabel('Agent setup'),
          const AgentSetupSection(),
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
          const SizedBox(height: 28),
          const _LogoutButton(),
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

class _LogoutButton extends ConsumerWidget {
  const _LogoutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(tokensProvider);
    return GestureDetector(
      onTap: () => _confirmAndLogout(context, ref),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.border),
        ),
        child: const Text(
          'Log out',
          style: TextStyle(
            color: Color(0xFFDC2626),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndLogout(BuildContext context, WidgetRef ref) async {
    final tokens = ref.read(tokensProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: tokens.drawerBg,
        title: Text(
          'Log out?',
          style: TextStyle(color: tokens.text, fontSize: 16),
        ),
        content: Text(
          'You will be signed out and your agent connection will be cleared from this phone.',
          style: TextStyle(color: tokens.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: tokens.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Log out',
              style: TextStyle(color: Color(0xFFDC2626)),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final auth = ref.read(authServiceProvider);
    final currentUser = auth.currentUser;

    // Clear session + cached agent connection before signing out so the router
    // doesn't briefly land on a stale "signed in but disconnected" frame.
    await ref.read(agentConnectionControllerProvider.notifier).disconnect();
    await ref.clearOnboardingDone(currentUser);
    await auth.signOut();
    // _AppRouter swaps to SignInScreen automatically once authStateProvider
    // emits a null user.
  }
}
