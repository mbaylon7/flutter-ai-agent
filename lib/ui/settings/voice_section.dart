import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/settings_provider.dart';
import 'package:stt_tts/state/voice_controller.dart';
import 'package:stt_tts/ui/settings/setting_tile.dart';

class VoiceSection extends ConsumerWidget {
  const VoiceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final tts = ref.watch(ttsServiceProvider);

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
            icon: Icons.record_voice_over,
            title: 'Voice',
            subtitle: settings.voiceKey ?? 'Default',
            trailing: const Icon(Icons.chevron_right, color: OcColors.textMeta),
            onTap: () async {
              final picked = await showModalBottomSheet<String>(
                context: context,
                backgroundColor: OcColors.surface,
                builder: (_) => SafeArea(
                  child: ListView(
                    shrinkWrap: true,
                    children: tts.voices.map((v) {
                      final key = '${v['name']}|${v['locale']}';
                      return ListTile(
                        title: Text(
                          v['name'] ?? '',
                          style: const TextStyle(color: OcColors.textPrimary),
                        ),
                        subtitle: Text(
                          v['locale'] ?? '',
                          style: const TextStyle(color: OcColors.textSubtitle),
                        ),
                        trailing: settings.voiceKey == key
                            ? const Icon(Icons.check, color: OcColors.accent)
                            : null,
                        onTap: () => Navigator.pop(context, key),
                      );
                    }).toList(),
                  ),
                ),
              );
              if (picked != null) {
                await tts.selectVoice(picked);
                await ref.read(settingsProvider.notifier).setVoiceKey(picked);
              }
            },
          ),
          const Divider(color: OcColors.borderTint, height: 1),
          SettingTile(
            icon: Icons.headphones,
            title: 'Wake word',
            subtitle: '"Hi OpenClaw" — uses extra battery',
            trailing: Switch(
              value: settings.wakeWordEnabled,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setWakeWord(v),
              activeColor: OcColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
