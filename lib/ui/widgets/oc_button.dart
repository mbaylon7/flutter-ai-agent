import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

enum OcButtonStyle { primary, secondary }

class OcButton extends StatelessWidget {
  const OcButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = OcButtonStyle.primary,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final OcButtonStyle style;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isPrimary = style == OcButtonStyle.primary;
    return GestureDetector(
      onTap: busy ? null : onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isPrimary ? OcColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: isPrimary ? null : Border.all(color: OcColors.borderTint),
          boxShadow: isPrimary && !busy
              ? const [
                  BoxShadow(color: Color(0x596CB0FF), blurRadius: 22),
                ]
              : null,
        ),
        child: busy
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: OcColors.bgBottom,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  color: isPrimary
                      ? OcColors.bgBottom
                      : OcColors.textSubtitle,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }
}
