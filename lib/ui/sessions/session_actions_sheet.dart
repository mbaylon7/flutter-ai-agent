import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/state/sessions_provider.dart';

/// Bottom-sheet content for long-press actions on a session row.
///
/// Mount via [showModalBottomSheet]:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   builder: (_) => SessionActionsSheet(session: session),
/// );
/// ```
class SessionActionsSheet extends ConsumerWidget {
  const SessionActionsSheet({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(sessionsProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle indicator
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: OcColors.borderTint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Session title label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                session.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: OcColors.textSubtitle,
                  fontSize: 12,
                ),
              ),
            ),

            const Divider(color: OcColors.borderTint, height: 1),

            // Rename
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: OcColors.accent),
              title: const Text(
                'Rename',
                style: TextStyle(color: OcColors.textPrimary),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await _showRenameDialog(context, ref, controller);
              },
            ),

            // Pin / Unpin toggle
            ListTile(
              leading: Icon(
                session.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: OcColors.accent,
              ),
              title: Text(
                session.pinned ? 'Unpin' : 'Pin',
                style: const TextStyle(color: OcColors.textPrimary),
              ),
              onTap: () {
                Navigator.of(context).pop();
                controller.setPinned(session.key, !session.pinned);
              },
            ),

            // Delete
            ListTile(
              leading: const Icon(Icons.delete_outline, color: OcColors.danger),
              title: const Text(
                'Delete',
                style: TextStyle(color: OcColors.danger),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await _showDeleteDialog(context, ref, controller);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    SessionsController controller,
  ) async {
    final textController = TextEditingController(text: session.title);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OcColors.surface,
        title: const Text(
          'Rename conversation',
          style: TextStyle(color: OcColors.textPrimary),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: textController,
            autofocus: true,
            style: const TextStyle(color: OcColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Conversation name',
              hintStyle: TextStyle(color: OcColors.textMeta),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: OcColors.borderTint),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: OcColors.accent),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: OcColors.textSubtitle),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Rename',
              style: TextStyle(color: OcColors.accent),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final newTitle = textController.text.trim();
      if (newTitle.isNotEmpty && newTitle != session.title) {
        await controller.rename(session.key, newTitle);
      }
    }
    textController.dispose();
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    SessionsController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OcColors.surface,
        title: const Text(
          'Delete conversation?',
          style: TextStyle(color: OcColors.textPrimary),
        ),
        content: Text(
          "Delete '${session.title}'? This can't be undone.",
          style: const TextStyle(color: OcColors.textBody),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: OcColors.textSubtitle),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: OcColors.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await controller.delete(session.key);
    }
  }
}
