import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/state/settings_provider.dart';
import 'package:stt_tts/state/theme_provider.dart';
import 'package:stt_tts/ui/settings/setting_tile.dart';

class PersonalitySection extends ConsumerWidget {
  const PersonalitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final tokens = ref.watch(tokensProvider);
    return SettingTile(
      icon: Icons.chat_bubble_outline,
      title: 'Tone',
      subtitle: switch (s.tone) {
        Tone.casual => 'Casual',
        Tone.professional => 'Professional',
        Tone.concise => 'Concise',
      },
      trailing: Icon(Icons.chevron_right, color: tokens.textMuted, size: 18),
      onTap: () async {
        final picked = await showModalBottomSheet<Tone>(
          context: context,
          backgroundColor: tokens.drawerBg,
          builder: (_) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: Tone.values
                  .map((t) => ListTile(
                        title: Text(
                          switch (t) {
                            Tone.casual => 'Casual',
                            Tone.professional => 'Professional',
                            Tone.concise => 'Concise',
                          },
                          style:
                              TextStyle(color: tokens.text, fontSize: 13),
                        ),
                        trailing: s.tone == t
                            ? Icon(Icons.check, color: tokens.accent)
                            : null,
                        onTap: () => Navigator.pop(context, t),
                      ))
                  .toList(),
            ),
          ),
        );
        if (picked != null) {
          await ref.read(settingsProvider.notifier).setTone(picked);
        }
      },
    );
  }
}
