import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/ui/settings/setting_tile.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: OcColors.overlayTint,
        border: Border.all(color: OcColors.borderTint),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        children: [
          SettingTile(
            icon: Icons.info_outline,
            title: 'Version',
            subtitle: '1.0.0-slice1',
          ),
          Divider(color: OcColors.borderTint, height: 1),
          SettingTile(
            icon: Icons.help_outline,
            title: 'Support',
          ),
        ],
      ),
    );
  }
}
