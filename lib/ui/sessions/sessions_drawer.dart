import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/design_tokens.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:stt_tts/state/theme_provider.dart';
import 'package:stt_tts/ui/sessions/session_actions_sheet.dart';
import 'package:stt_tts/ui/sessions/session_row.dart';
import 'package:stt_tts/ui/sessions/session_search_bar.dart';
import 'package:stt_tts/ui/settings/settings_screen.dart';

/// Sessions drawer — themed via [OcTokens]. Layout mirrors the HTML
/// `.drawer-sheet`: dark `--drawer-bg` in dark mode, light in light mode,
/// 85% width, all type at 13px / 11.5px per the design spec.
class SessionsDrawer extends ConsumerWidget {
  const SessionsDrawer({super.key, this.width});

  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mq = MediaQuery.of(context);
    final drawerWidth = width ?? mq.size.width * 0.85;
    final tokens = ref.watch(tokensProvider);
    final state = ref.watch(sessionsProvider);
    final currentKey = ref.watch(currentSessionProvider);

    return Container(
      width: drawerWidth,
      color: tokens.drawerBg,
      child: Column(
        children: [
          SizedBox(height: mq.padding.top + 8),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: SessionSearchBar(),
          ),
          _NewChatRow(
            onTap: () {
              ref.read(currentSessionProvider.notifier).state = null;
              Navigator.of(context).maybePop();
            },
          ),
          Expanded(child: _Body(state: state, currentKey: currentKey)),
          _Footer(bottomPadding: mq.padding.bottom),
        ],
      ),
    );
  }
}

class _NewChatRow extends ConsumerWidget {
  const _NewChatRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(tokensProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.edit_outlined, color: tokens.text, size: 18),
              const SizedBox(width: 12),
              Text(
                'New chat',
                style: TextStyle(
                  color: tokens.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.currentKey});

  final SessionsState state;
  final String? currentKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(tokensProvider);
    final visible = state.visible;

    return visible.when(
      loading: () => Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: tokens.accent),
        ),
      ),
      error: (err, st) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Couldn't load conversations",
              style: TextStyle(color: tokens.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => ref.invalidate(sessionsProvider),
              child: Text(
                'Retry',
                style: TextStyle(color: tokens.accent, fontSize: 13),
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
              style: TextStyle(color: tokens.textMuted, fontSize: 13),
            ),
          );
        }

        final ordered = [
          ...sessions.where((s) => s.pinned),
          ...sessions.where((s) => !s.pinned),
        ];
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          children: [
            const _SectionLabel(label: 'Chats'),
            ...ordered.map((s) => _rowFor(context, ref, s, currentKey)),
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
          backgroundColor: ref.read(tokensProvider).drawerBg,
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

class _SectionLabel extends ConsumerWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(tokensProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Text(
        label,
        style: TextStyle(
          color: tokens.textMuted,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.005 * 11.5,
        ),
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(tokensProvider);
    return Container(
      padding: EdgeInsets.only(
        bottom: bottomPadding + 12,
        top: 12,
        left: 20,
        right: 12,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.surfaceActive,
              shape: BoxShape.circle,
            ),
            child: Text(
              'M',
              style: TextStyle(
                color: tokens.text,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Marvin',
              style: TextStyle(
                color: tokens.text,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: Icon(Icons.settings_outlined,
                color: tokens.textMuted, size: 18),
            onPressed: () {
              final navigator = Navigator.of(context);
              navigator.maybePop();
              Future.delayed(const Duration(milliseconds: 200), () {
                navigator.push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              });
            },
          ),
        ],
      ),
    );
  }
}
