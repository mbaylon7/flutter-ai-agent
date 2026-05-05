import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:stt_tts/ui/sessions/session_actions_sheet.dart';
import 'package:stt_tts/ui/sessions/session_row.dart';
import 'package:stt_tts/ui/sessions/session_search_bar.dart';

/// Sessions drawer.
///
/// Designed to be mounted as a [Drawer] child (Task 9 wires the gesture).
/// Takes an explicit [width] so the parent controls how wide the panel is.
///
/// Does NOT integrate with HomeShell — that is Task 9's responsibility.
class SessionsDrawer extends ConsumerWidget {
  const SessionsDrawer({super.key, this.width});

  /// Optional explicit width. Falls back to [MediaQuery] 80% if omitted.
  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mq = MediaQuery.of(context);
    final drawerWidth = width ?? mq.size.width * 0.80;

    final state = ref.watch(sessionsProvider);
    final currentKey = ref.watch(currentSessionProvider);

    return Container(
      width: drawerWidth,
      color: OcColors.surface,
      child: Column(
        children: [
          // ----------------------------------------------------------------
          // Top bar
          // ----------------------------------------------------------------
          SizedBox(
            height: 56 + mq.padding.top,
            child: Padding(
              padding: EdgeInsets.only(top: mq.padding.top),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Conversations',
                      style: TextStyle(
                        color: OcColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'New conversation',
                    child: IconButton(
                      icon: const Icon(Icons.add_comment_outlined,
                          color: OcColors.textPrimary, size: 22),
                      onPressed: () {
                        ref.read(currentSessionProvider.notifier).state =
                            null;
                        Navigator.of(context).maybePop();
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),

          // ----------------------------------------------------------------
          // Search + filter chips
          // ----------------------------------------------------------------
          const SessionSearchBar(),

          // ----------------------------------------------------------------
          // Body
          // ----------------------------------------------------------------
          Expanded(child: _Body(state: state, currentKey: currentKey)),

          // ----------------------------------------------------------------
          // Footer
          // ----------------------------------------------------------------
          _Footer(bottomPadding: mq.padding.bottom),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — loading / error / list
// ---------------------------------------------------------------------------

class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.currentKey});

  final SessionsState state;
  final String? currentKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = state.visible;

    return visible.when(
      loading: () => const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: OcColors.accent,
          ),
        ),
      ),
      error: (err, st) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Couldn't load conversations",
              style: TextStyle(color: OcColors.textSubtitle),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => ref.invalidate(sessionsProvider),
              child: const Text(
                'Retry',
                style: TextStyle(color: OcColors.accent),
              ),
            ),
          ],
        ),
      ),
      data: (sessions) {
        if (sessions.isEmpty) {
          final hasQuery = state.query.isNotEmpty;
          return Center(
            child: Text(
              hasQuery ? 'No matches' : 'No conversations yet',
              style: const TextStyle(color: OcColors.textSubtitle),
            ),
          );
        }

        final pinned = sessions.where((s) => s.pinned).toList();
        final recent = sessions.where((s) => !s.pinned).toList();

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            if (pinned.isNotEmpty) ...[
              _SectionHeader(label: '📌 Pinned'),
              ...pinned.map((s) => _rowFor(context, ref, s, currentKey)),
            ],
            if (recent.isNotEmpty) ...[
              _SectionHeader(label: 'Recent'),
              ...recent.map((s) => _rowFor(context, ref, s, currentKey)),
            ],
          ],
        );
      },
    );
  }

  Widget _rowFor(
    BuildContext context,
    WidgetRef ref,
    Session session,
    String? currentKey,
  ) {
    return SessionRow(
      key: ValueKey(session.key),
      session: session,
      active: session.key == currentKey,
      onTap: () {
        ref.read(currentSessionProvider.notifier).state = session.key;
        Navigator.of(context).maybePop();
      },
      onLongPress: () {
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: OcColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (_) => UncontrolledProviderScope(
            container: ProviderScope.containerOf(context),
            child: SessionActionsSheet(session: session),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Text(
        label,
        style: const TextStyle(
          color: OcColors.textMeta,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer: avatar + name + settings gear
// ---------------------------------------------------------------------------

class _Footer extends StatelessWidget {
  const _Footer({required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56 + bottomPadding,
      padding: EdgeInsets.only(
        bottom: bottomPadding,
        left: 12,
        right: 4,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: OcColors.borderTint)),
      ),
      child: Row(
        children: [
          // Avatar circle
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: OcColors.accent,
              shape: BoxShape.circle,
            ),
            child: const Text(
              'M',
              style: TextStyle(
                color: OcColors.bgBottom,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Marvin',
              style: TextStyle(
                color: OcColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          // Settings gear — deferred to slice 1D
          Tooltip(
            message: 'Settings coming soon',
            child: IconButton(
              icon: const Icon(Icons.settings_outlined,
                  color: OcColors.textMeta, size: 20),
              onPressed: null, // disabled — slice 1D
            ),
          ),
        ],
      ),
    );
  }
}
