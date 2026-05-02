import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/settings_provider.dart';
import 'package:stt_tts/ui/settings/setting_tile.dart';

class PersonalitySection extends ConsumerWidget {
  const PersonalitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: OcColors.overlayTint,
        border: Border.all(color: OcColors.borderTint),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SettingTile(
        icon: Icons.chat_bubble_outline,
        title: 'Tone',
        subtitle: switch (s.tone) {
          Tone.casual => 'Casual',
          Tone.professional => 'Professional',
          Tone.concise => 'Concise',
        },
        trailing: const Icon(Icons.chevron_right, color: OcColors.textMeta),
        onTap: () async {
          final picked = await showModalBottomSheet<Tone>(
            context: context,
            backgroundColor: OcColors.surface,
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
                            style: const TextStyle(color: OcColors.textPrimary),
                          ),
                          trailing: s.tone == t
                              ? const Icon(Icons.check, color: OcColors.accent)
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
      ),
    );
  }
}
