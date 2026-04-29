import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/repositories/session_repository.dart';
import 'package:stt_tts/state/sessions_provider.dart';

class SessionSearchBar extends ConsumerStatefulWidget {
  const SessionSearchBar({super.key});

  @override
  ConsumerState<SessionSearchBar> createState() => _SessionSearchBarState();
}

class _SessionSearchBarState extends ConsumerState<SessionSearchBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    ref.read(sessionsProvider.notifier).setQuery(_controller.text);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(
      sessionsProvider.select((s) => s.filter),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search field
          TextField(
            controller: _controller,
            style: const TextStyle(
              color: OcColors.textPrimary,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'Search conversations…',
              hintStyle: const TextStyle(color: OcColors.textMeta),
              prefixIcon: const Icon(Icons.search, color: OcColors.textMeta, size: 18),
              filled: true,
              fillColor: OcColors.overlayTint,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: OcColors.borderTint),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: OcColors.borderTint),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: OcColors.accent),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Filter chips row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: SessionFilter.values
                  .map((f) => _FilterChip(
                        label: _filterLabel(f),
                        active: filter == f,
                        onTap: () => ref
                            .read(sessionsProvider.notifier)
                            .setFilter(f),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _filterLabel(SessionFilter f) {
    switch (f) {
      case SessionFilter.all:
        return 'All';
      case SessionFilter.voice:
        return 'Voice';
      case SessionFilter.text:
        return 'Text';
      case SessionFilter.pinned:
        return 'Pinned';
    }
  }
}

// ---------------------------------------------------------------------------
// Individual filter chip
// ---------------------------------------------------------------------------

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? OcColors.accent : OcColors.overlayTint,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? OcColors.accent : OcColors.borderTint,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? OcColors.bgBottom : OcColors.textBody,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
