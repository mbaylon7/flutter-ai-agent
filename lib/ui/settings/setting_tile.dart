import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

class SettingTile extends StatelessWidget {
  const SettingTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: OcColors.overlayTint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: OcColors.textSubtitle, size: 14),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(color: OcColors.textPrimary, fontSize: 13)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: const TextStyle(color: OcColors.textSubtitle, fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
