import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/state/theme_provider.dart';
import 'package:stt_tts/ui/settings/setting_tile.dart';

class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(tokensProvider);
    final mode = ref.watch(appThemeProvider);
    final platform = ref.watch(platformBrightnessProvider);

    final effective = mode == AppThemeMode.system
        ? platform
        : (mode == AppThemeMode.dark ? Brightness.dark : Brightness.light);
    final isLight = effective == Brightness.light;

    return SettingTile(
      icon: Icons.wb_sunny_outlined,
      title: 'Light mode',
      subtitle: 'Switch between light and dark theme',
      trailing: _Switch(
        value: isLight,
        onChanged: (next) {
          ref.read(appThemeProvider.notifier).setMode(
                next ? AppThemeMode.light : AppThemeMode.dark,
              );
        },
        toggleOn: tokens.toggleOn,
        toggleOff: tokens.border,
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.value,
    required this.onChanged,
    required this.toggleOn,
    required this.toggleOff,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color toggleOn;
  final Color toggleOff;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        width: 46,
        height: 27,
        decoration: BoxDecoration(
          color: value ? toggleOn : toggleOff,
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
