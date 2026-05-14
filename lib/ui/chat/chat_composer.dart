import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/domain/repositories/chat_repository.dart';
import 'package:stt_tts/state/repositories_provider.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:uuid/uuid.dart';

/// Minimal chat input for the unified voice-focused shell.
///
/// No border, no background, no placeholder. A thicker-than-default blinking
/// cursor sits centered when empty; as the user types the text grows outward
/// from the center. Submit via the keyboard's send key.
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({super.key});

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Request focus so the system caret is visible immediately when the user
    // flips to chat mode. The keyboard opens; system back dismisses it but
    // preserves focus, so the caret keeps blinking.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    var key = ref.read(currentSessionProvider);
    if (key == null) {
      key = 'agent:main:${const Uuid().v4()}';
      ref.read(currentSessionProvider.notifier).state = key;
    }

    final knownKeys = ref
            .read(sessionsProvider)
            .sessions
            .valueOrNull
            ?.map((s) => s.key)
            .toSet() ??
        const <String>{};
    final isFirstMessage = !knownKeys.contains(key);

    _controller.clear();

    try {
      await ref
          .read(chatRepositoryProvider)
          .send(sessionKey: key, text: text);

      if (isFirstMessage) {
        unawaited(_popSessionWhenAiResponds(
          sessionKey: key,
          derivedTitle: ChatRepository.deriveTitle(text),
        ));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Couldn't send. Tap to retry."),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () {
              _controller.text = text;
              _focusNode.requestFocus();
            },
          ),
        ),
      );
    }
  }

  Future<void> _popSessionWhenAiResponds({
    required String sessionKey,
    required String derivedTitle,
  }) async {
    try {
      final repo = ref.read(chatRepositoryProvider);
      await repo.messages(sessionKey).firstWhere(
        (list) {
          return list.any(
            (m) =>
                m.role == Role.assistant &&
                m.parts.whereType<TextPart>().any((p) => p.text.isNotEmpty),
          );
        },
      ).timeout(const Duration(seconds: 60));
    } catch (_) {
      return;
    }

    if (!mounted) return;
    ref.read(sessionsProvider.notifier).upsertLocal(
          Session(
            key: sessionKey,
            title: derivedTitle,
            updatedAt: DateTime.now(),
            kind: 'direct',
            pinned: false,
          ),
        );
    unawaited(ref.read(sessionsProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
      child: TextField(
        key: const Key('composer_text_field'),
        controller: _controller,
        focusNode: _focusNode,
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        minLines: 1,
        maxLines: 4,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _send(),
        cursorWidth: 3,
        cursorRadius: const Radius.circular(1.5),
        cursorColor: OcColors.textPrimary,
        style: const TextStyle(
          color: OcColors.textPrimary,
          fontSize: 16,
          height: 1.4,
        ),
        // Collapsed decoration → no underline, no border, no fill, no
        // contentPadding from the decorator itself. We add our own padding
        // around the TextField at the parent level if needed.
        decoration: const InputDecoration.collapsed(hintText: null),
      ),
    );
  }
}
