import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/domain/repositories/chat_repository.dart';
import 'package:stt_tts/state/messages_provider.dart';
import 'package:stt_tts/state/repositories_provider.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:uuid/uuid.dart';

/// Bottom composer for chat mode.
///
/// Two visual states:
///   • Unfocused + empty → almost invisible: a faint "Ask anything…" hint with
///     a subtle blinking caret so the user knows tapping reveals a keyboard.
///   • Focused or has text → full pill style with a send button.
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({super.key});

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  void _onTextChanged() {
    final next = _controller.text.trim().isNotEmpty;
    if (next != _hasText) setState(() => _hasText = next);
  }

  void _onFocusChanged() {
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _isStreaming(List<Message> messages) {
    if (messages.isEmpty) return false;
    final last = messages.last;
    return last.role == Role.assistant &&
        last.streaming == StreamingState.partial;
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
    _focusNode.unfocus();

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
    final key = ref.watch(currentSessionProvider);

    bool streaming = false;
    if (key != null) {
      final msgs = ref.watch(messagesProvider(key));
      streaming = msgs.valueOrNull != null && _isStreaming(msgs.value!);
    }

    final sendEnabled = _hasText && !streaming;
    final subtle = !_focused && !_hasText;

    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: subtle
              ? Colors.transparent
              : OcColors.surfaceMuted,
          borderRadius: BorderRadius.circular(28),
          border: subtle
              ? Border.all(
                  color: OcColors.textMeta.withValues(alpha: 0.18),
                  width: 1,
                )
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Real TextField — always present, becomes opaque on focus.
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: subtle ? 0 : 1,
                    child: TextField(
                      key: const Key('composer_text_field'),
                      controller: _controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: sendEnabled ? (_) => _send() : null,
                      style: const TextStyle(
                        color: OcColors.textPrimary,
                        fontSize: 15,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Ask anything…',
                        hintStyle: TextStyle(color: OcColors.textMeta),
                        isCollapsed: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  // Subtle "type here" hint shown only when unfocused + empty.
                  if (subtle)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _focusNode.requestFocus,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: _SubtleHint(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!subtle)
              _SendButton(
                enabled: sendEnabled,
                onSend: sendEnabled ? _send : null,
              ),
          ],
        ),
      ),
    );
  }
}

/// "Ask anything…" with a faint blinking caret. Visible when the composer is
/// idle so the user notices a text field is present.
class _SubtleHint extends StatefulWidget {
  const _SubtleHint();

  @override
  State<_SubtleHint> createState() => _SubtleHintState();
}

class _SubtleHintState extends State<_SubtleHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (_, child) {
            // Square-wave blink: visible for the first half, hidden for the
            // second. Smooth fade would look fancy but a sharp blink reads as
            // a caret more clearly.
            final visible = _controller.value < 0.55;
            return Opacity(
              opacity: visible ? 0.55 : 0.0,
              child: Container(
                width: 1.5,
                height: 16,
                color: OcColors.textPrimary,
              ),
            );
          },
        ),
        const SizedBox(width: 6),
        Text(
          'Ask anything…',
          style: TextStyle(
            color: OcColors.textMeta.withValues(alpha: 0.75),
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onSend});

  final bool enabled;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 2, bottom: 2),
      child: Material(
        color: enabled ? OcColors.textPrimary : OcColors.textMeta,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onSend : null,
          child: const SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              Icons.arrow_upward_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
