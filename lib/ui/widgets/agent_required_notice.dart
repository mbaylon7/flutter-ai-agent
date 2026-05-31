import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/design_tokens.dart';
import 'package:stt_tts/state/theme_provider.dart';
import 'package:stt_tts/ui/settings/settings_screen.dart';

/// Theme-aware "no agent connected" prompt with a **Connect** action that opens
/// Settings. Styled via [OcTokens] so it follows the black/white theme
/// (dark surface + light text in dark mode; light surface + dark text in light
/// mode). Shown on launch when the home screen has no agent, and when the user
/// taps New chat without one.
void showAgentRequiredNotice(BuildContext context, WidgetRef ref) {
  final tokens = ref.read(tokensProvider);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: tokens.drawerBg,
      elevation: 6,
      duration: const Duration(seconds: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: tokens.border),
      ),
      content: Text(
        'No agent connected — connect one to start chatting.',
        style: TextStyle(
          color: tokens.text,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      action: SnackBarAction(
        label: 'Connect',
        textColor: tokens.accent,
        onPressed: () => navigator.push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
      ),
    ),
  );
}
