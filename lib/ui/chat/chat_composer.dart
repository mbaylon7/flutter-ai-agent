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
import 'package:stt_tts/state/ui_mode_provider.dart';
import 'package:uuid/uuid.dart';

/// Bottom composer: pill-shaped text field with a trailing icon that swaps
/// between mic (when empty) and send (when typing).
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({super.key});

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final next = _controller.text.trim().isNotEmpty;
    if (next != _hasText) setState(() => _hasText = next);
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

    // The key may already exist because voice mode (home_shell._ensureSession)
    // pre-generates a UUID, or because the user has been chatting in this
    // session. Detect "first message in this session" by checking whether the
    // sidebar already knows about this key.
    final knownKeys = ref
            .read(sessionsProvider)
            .sessions
            .valueOrNull
            ?.map((s) => s.key)
            .toSet() ??
        const <String>{};
    final isFirstMessage = !knownKeys.contains(key);

    debugPrint(
      '[composer] _send key=$key isFirstMessage=$isFirstMessage knownCount=${knownKeys.length}',
    );

    _controller.clear();
    _focusNode.unfocus();

    try {
      await ref
          .read(chatRepositoryProvider)
          .send(sessionKey: key, text: text);

      if (isFirstMessage) {
        // Pop the session into the sidebar only AFTER the AI has actually
        // started replying — not when the user merely typed something. This
        // avoids cluttering the history with abandoned/failed sends.
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

  /// Wait for the assistant to produce any visible content, then insert the
  /// session into the sidebar. Times out after 60 s so a hung send doesn't
  /// leak this listener.
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
    } catch (e) {
      debugPrint('[composer] AI never responded ($e); skipping sidebar upsert');
      return;
    }

    if (!mounted) return;
    debugPrint('[composer] AI responded — upserting "$derivedTitle"');
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

    return Container(
      color: OcColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: OcColors.surfaceMuted,
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
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
              _TrailingAction(
                hasText: _hasText,
                streaming: streaming,
                onSend: sendEnabled ? _send : null,
                onMic: () =>
                    ref.read(uiModeProvider.notifier).state = UiMode.voice,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrailingAction extends StatelessWidget {
  const _TrailingAction({
    required this.hasText,
    required this.streaming,
    required this.onSend,
    required this.onMic,
  });

  final bool hasText;
  final bool streaming;
  final VoidCallback? onSend;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    if (hasText) {
      final enabled = onSend != null && !streaming;
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
    return IconButton(
      key: const Key('composer_mic_button'),
      tooltip: 'Switch to voice',
      onPressed: onMic,
      icon: const Icon(Icons.mic_none_rounded),
      color: OcColors.textPrimary,
      iconSize: 22,
    );
  }
}
