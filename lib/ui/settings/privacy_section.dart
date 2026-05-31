import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/state/connection_provider.dart';
import 'package:stt_tts/state/repositories_provider.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:stt_tts/state/theme_provider.dart';
import 'package:stt_tts/ui/settings/setting_tile.dart';

class PrivacySection extends ConsumerWidget {
  const PrivacySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(tokensProvider);
    return Column(
      children: [
        SettingTile(
          icon: Icons.delete_outline,
          title: 'Clear local cache',
          subtitle: 'Conversation list on this phone',
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: tokens.drawerBg,
                title: Text(
                  'Clear local cache?',
                  style: TextStyle(color: tokens.text, fontSize: 16),
                ),
                content: Text(
                  'Removes the cached sessions list on this phone. '
                  'Your conversations on the gateway are not affected.',
                  style: TextStyle(color: tokens.textMuted, fontSize: 13),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Cancel',
                        style: TextStyle(color: tokens.textMuted)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child:
                        Text('Clear', style: TextStyle(color: tokens.accent)),
                  ),
                ],
              ),
            );
            if (ok == true) {
              final store = ref.read(localStoreProvider);
              await store.clear();
              ref.invalidate(sessionsProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Local cache cleared')),
                );
              }
            }
          },
        ),
        const SizedBox(height: 8),
        SettingTile(
          icon: Icons.power_settings_new,
          title: 'Unpair this device',
          subtitle: 'Removes the device token from this phone',
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: tokens.drawerBg,
                title: Text(
                  'Unpair this device?',
                  style: TextStyle(color: tokens.text, fontSize: 16),
                ),
                content: Text(
                  'You will need to pair again with the gateway URL, port, and token.',
                  style: TextStyle(color: tokens.textMuted, fontSize: 13),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Cancel',
                        style: TextStyle(color: tokens.textMuted)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Unpair',
                        style: TextStyle(color: Color(0xFFE25555))),
                  ),
                ],
              ),
            );
            if (ok == true) {
              await ref
                  .read(agentConnectionControllerProvider.notifier)
                  .disconnect();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Device unpaired')),
                );
              }
            }
          },
        ),
      ],
    );
  }
}
