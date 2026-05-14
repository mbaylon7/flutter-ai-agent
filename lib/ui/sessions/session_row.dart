import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/state/theme_provider.dart';

/// Formats [updatedAt] into a human-readable relative/absolute label.
///
/// Pass [now] in tests so the output is deterministic.
String formatSessionTime(DateTime updatedAt, [DateTime? now]) {
  final base = now ?? DateTime.now();
  final diff = base.difference(updatedAt);

  if (diff.inMinutes < 60) return 'now';

  final today = DateTime(base.year, base.month, base.day);
  final itemDay = DateTime(updatedAt.year, updatedAt.month, updatedAt.day);

  if (itemDay == today) {
    return DateFormat('h:mm a').format(updatedAt);
  }

  final yesterday = today.subtract(const Duration(days: 1));
  if (itemDay == yesterday) return 'Yesterday';

  if (diff.inDays < 7) return DateFormat.E().format(updatedAt);

  if (updatedAt.year == base.year) {
    return DateFormat('MMM d').format(updatedAt);
  }

  return DateFormat('MMM d, y').format(updatedAt);
}

class SessionRow extends ConsumerWidget {
  const SessionRow({
    super.key,
    required this.session,
    required this.active,
    required this.onTap,
    required this.onLongPress,
  });

  final Session session;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(tokensProvider);
    final timeLabel = formatSessionTime(session.updatedAt);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        key: active ? const Key('session_row_active') : null,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: active ? tokens.surfaceActive : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                session.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.text,
                  fontWeight: FontWeight.w400,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              timeLabel,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
