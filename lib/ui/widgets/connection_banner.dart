// ignore_for_file: implementation_imports
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/state/connection_provider.dart';

/// Thin status banner shown at the top of the chat shell.
///
/// - `connecting`    → amber bar "Reconnecting…"
/// - `authenticated` → hidden
/// - `disconnected` / `failed` → amber bar "Offline — tap to retry"
/// - `idle`          → hidden
/// - autoReconnect.error → red bar "Couldn't reconnect — tap to retry"
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reconnect = ref.watch(autoReconnectControllerProvider);
    final connState = ref.watch(connectionStateProvider);

    // autoReconnect error trumps everything.
    if (reconnect.hasError) {
      return _Banner(
        color: OcColors.danger,
        icon: Icons.cloud_off_rounded,
        text: "Couldn't reconnect — tap to retry",
        onTap: () => ref.read(autoReconnectControllerProvider.notifier).retry(),
      );
    }

    final cs = connState.valueOrNull;
    if (cs == null) return const SizedBox.shrink();

    switch (cs) {
      case ConnectionState.connecting:
        return _Banner(
          color: OcColors.warn,
          icon: Icons.sync_rounded,
          text: 'Reconnecting…',
          trailing: const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: OcColors.bgBottom,
            ),
          ),
        );

      case ConnectionState.disconnected:
      case ConnectionState.failed:
        return _Banner(
          color: OcColors.warn,
          icon: Icons.cloud_off_rounded,
          text: 'Offline — tap to retry',
          onTap: () =>
              ref.read(autoReconnectControllerProvider.notifier).retry(),
        );

      case ConnectionState.authenticated:
      case ConnectionState.idle:
        return const SizedBox.shrink();
    }
  }
}

// ---------------------------------------------------------------------------
// _Banner — the visual bar widget
// ---------------------------------------------------------------------------

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.icon,
    required this.text,
    this.trailing,
    this.onTap,
  });

  final Color color;
  final IconData icon;
  final String text;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        height: 36,
        color: color,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(icon, size: 15, color: OcColors.bgBottom),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: OcColors.bgBottom,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 6),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
