import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/connection_provider.dart';
import 'package:stt_tts/state/repositories_provider.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:stt_tts/ui/onboarding/welcome_screen.dart';
import 'package:stt_tts/ui/settings/setting_tile.dart';

class PrivacySection extends ConsumerWidget {
  const PrivacySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: OcColors.overlayTint,
        border: Border.all(color: OcColors.borderTint),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          SettingTile(
            icon: Icons.delete_outline,
            title: 'Clear local cache',
            subtitle: 'Conversation list on this phone',
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: OcColors.surface,
                  title: const Text('Clear local cache?',
                      style: TextStyle(color: OcColors.textPrimary)),
                  content: const Text(
                    'Removes the cached sessions list on this phone. '
                    'Your conversations on the gateway are not affected.',
                    style: TextStyle(color: OcColors.textSubtitle),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                final store = ref.read(localStoreProvider);
                await store.clear();
                // Force the sessions list to refresh from the gateway.
                ref.invalidate(sessionsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Local cache cleared')),
                  );
                }
              }
            },
          ),
          const Divider(color: OcColors.borderTint, height: 1),
          SettingTile(
            icon: Icons.power_settings_new,
            title: 'Unpair this device',
            subtitle: 'Removes the device token from this phone',
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: OcColors.surface,
                  title: const Text('Unpair this device?',
                      style: TextStyle(color: OcColors.textPrimary)),
                  content: const Text(
                    'You will need to pair again with the gateway URL and token.',
                    style: TextStyle(color: OcColors.textSubtitle),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Unpair',
                          style: TextStyle(color: OcColors.danger)),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                final store = ref.read(secureStoreProvider);
                await store.delete('oc.deviceToken');
                await store.delete('oc.wsUrl');
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                    (_) => false,
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
