import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:stt_tts/state/theme_provider.dart';

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
    final tokens = ref.watch(tokensProvider);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tokens.border, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: tokens.textMuted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              style: TextStyle(color: tokens.text, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search for chats',
                hintStyle: TextStyle(color: tokens.textMuted, fontSize: 13),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
