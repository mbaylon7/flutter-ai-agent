import 'package:flutter/material.dart';
import 'package:stt_tts/ui/settings/setting_tile.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SettingTile(
          icon: Icons.info_outline,
          title: 'Version',
          subtitle: '1.0.0',
        ),
        SizedBox(height: 8),
        SettingTile(
          icon: Icons.help_outline,
          title: 'Support',
        ),
      ],
    );
  }
}
