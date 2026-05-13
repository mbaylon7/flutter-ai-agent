import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/session.dart';

// ---------------------------------------------------------------------------
// Time formatting helper
// ---------------------------------------------------------------------------

/// Formats [updatedAt] into a human-readable relative/absolute label.
///
/// Pass [now] in tests so the output is deterministic.
// @visibleForTesting — accessible from tests via the public import.
String formatSessionTime(DateTime updatedAt, [DateTime? now]) {
  final base = now ?? DateTime.now();
  final diff = base.difference(updatedAt);

  if (diff.inMinutes < 60) return 'now';

  final today = DateTime(base.year, base.month, base.day);
  final itemDay =
      DateTime(updatedAt.year, updatedAt.month, updatedAt.day);

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

// ---------------------------------------------------------------------------
// Session row
// ---------------------------------------------------------------------------

class SessionRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final timeLabel = formatSessionTime(session.updatedAt);

    final decoration = active
        ? BoxDecoration(
            color: OcColors.borderTint.withValues(alpha: 0.5),
            border: const Border(
              left: BorderSide(color: OcColors.accent, width: 2),
            ),
          )
        : null;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        key: active ? const Key('session_row_active') : null,
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: decoration,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: title + time
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: OcColors.textBody,
                            fontWeight: FontWeight.w400,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        timeLabel,
                        style: const TextStyle(
                          color: OcColors.textMeta,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),

                  // Row 2: preview (only if present)
                  if (session.lastPreview != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      session.lastPreview!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OcColors.textSubtitle,
                        fontSize: 12,
                      ),
                    ),
                  ],

                  // Row 3: meta (pin + Text badge)
                  if (session.pinned) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (session.pinned)
                          const Text('📌',
                              style: TextStyle(fontSize: 10)),
                        const SizedBox(width: 4),
                        _SmallBadge(label: 'Text'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small badge pill (e.g. "Text")
// ---------------------------------------------------------------------------

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: OcColors.overlayTint,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: OcColors.borderTint),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: OcColors.textMeta,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
