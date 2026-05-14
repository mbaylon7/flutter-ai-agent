import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/state/settings_provider.dart';
import 'package:stt_tts/state/theme_provider.dart';
import 'package:stt_tts/state/voice_controller.dart';
import 'package:stt_tts/ui/settings/setting_tile.dart';

class VoiceSection extends ConsumerWidget {
  const VoiceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final tokens = ref.watch(tokensProvider);
    final tts = ref.watch(ttsServiceProvider);

    return Column(
      children: [
        SettingTile(
          icon: Icons.record_voice_over_outlined,
          title: 'Voice',
          subtitle: settings.voiceKey ?? 'Default',
          trailing:
              Icon(Icons.chevron_right, color: tokens.textMuted, size: 18),
          onTap: () async {
            final picked = await showModalBottomSheet<String>(
              context: context,
              backgroundColor: tokens.drawerBg,
              builder: (_) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: tts.voices.map((v) {
                    final key = '${v['name']}|${v['locale']}';
                    final label = v['label'] ?? v['name'] ?? '';
                    return ListTile(
                      title: Text(label,
                          style: TextStyle(color: tokens.text, fontSize: 13)),
                      subtitle: Text(
                        '${v['name']} · ${v['locale']}',
                        style: TextStyle(
                            color: tokens.textMuted, fontSize: 11.5),
                      ),
                      trailing: settings.voiceKey == key
                          ? Icon(Icons.check, color: tokens.accent)
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
        const SizedBox(height: 8),
        SettingTile(
          icon: Icons.headphones_outlined,
          title: 'Wake word',
          subtitle: '"Hi OpenClaw" — uses extra battery',
          trailing: _Switch(
            value: settings.wakeWordEnabled,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setWakeWord(v),
          ),
        ),
      ],
    );
  }
}

class _Switch extends ConsumerWidget {
  const _Switch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(tokensProvider);
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        width: 46,
        height: 27,
        decoration: BoxDecoration(
          color: value ? tokens.toggleOn : tokens.border,
          borderRadius: BorderRadius.circular(14),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Container(
              width: 23,
              height: 23,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.15),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
