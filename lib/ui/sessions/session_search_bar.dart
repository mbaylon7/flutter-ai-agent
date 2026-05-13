import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
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
    // Reference design: pill-shaped white search field; no filter chips.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        controller: _controller,
        style: const TextStyle(
          color: OcColors.textPrimary,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: 'Search for chats',
          hintStyle: const TextStyle(color: OcColors.textSubtitle),
          prefixIcon: const Icon(Icons.search,
              color: OcColors.textSubtitle, size: 20),
          filled: true,
          fillColor: OcColors.surface,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
