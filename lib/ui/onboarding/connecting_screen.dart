import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/connection_provider.dart';
import 'package:stt_tts/ui/onboarding/ready_screen.dart';
import 'package:stt_tts/ui/widgets/oc_button.dart';

class ConnectingScreen extends ConsumerWidget {
  const ConnectingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(pairControllerProvider, (prev, next) {
      next.whenOrNull(
        data: (hello) {
          if (hello != null) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const ReadyScreen()),
              (_) => false,
            );
          }
        },
      );
    });
    final state = ref.watch(pairControllerProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: ocBackgroundGradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: state.when(
                loading: () => const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 80,
                      width: 80,
                      child: CircularProgressIndicator(color: OcColors.accent),
                    ),
                    SizedBox(height: 22),
                    Text(
                      'Pairing this device…',
                      style: TextStyle(
                        color: OcColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                data: (_) => const SizedBox(),
                error: (e, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: OcColors.danger, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      "Couldn't pair",
                      style: TextStyle(
                        color: OcColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      e.toString(),
                      style: const TextStyle(
                        color: OcColors.textSubtitle,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    OcButton(
                      label: 'Try again',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
