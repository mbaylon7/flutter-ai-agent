import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/state/messages_provider.dart';
import 'package:stt_tts/state/repositories_provider.dart';
import 'package:stt_tts/state/sessions_provider.dart';

/// Bottom composer bar: mic stub + text field + send button.
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
    final key = ref.read(currentSessionProvider);
    if (key == null) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    _focusNode.unfocus();

    try {
      await ref
          .read(chatRepositoryProvider)
          .send(sessionKey: key, text: text);
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

  @override
  Widget build(BuildContext context) {
    final key = ref.watch(currentSessionProvider);

    // Detect if there's a streaming message to disable the send button.
    bool streaming = false;
    if (key != null) {
      final msgs = ref.watch(messagesProvider(key));
      streaming = msgs.valueOrNull != null && _isStreaming(msgs.value!);
    }

    final sendEnabled = _hasText && !streaming;

    return Container(
      decoration: const BoxDecoration(
        color: OcColors.surface,
        border: Border(top: BorderSide(color: OcColors.borderTint)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Mic stub — disabled, slice 1C will wire it
            Tooltip(
              message: 'Voice mode coming in slice 1C',
              child: IconButton(
                // TODO(slice-1c): wire to STT toggle
                onPressed: null,
                icon: const Icon(Icons.mic_outlined),
                color: OcColors.accent,
                disabledColor: OcColors.accent.withAlpha(77),
                iconSize: 24,
              ),
            ),
            // Text field
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
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  hintStyle: const TextStyle(color: OcColors.textMeta),
                  filled: true,
                  fillColor: OcColors.overlayTint,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: OcColors.borderTint),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: OcColors.borderTint),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: OcColors.accent),
                  ),
                ),
              ),
            ),
            // Send button
            IconButton(
              key: const Key('composer_send_button'),
              onPressed: sendEnabled ? _send : null,
              icon: const Icon(Icons.send_rounded),
              color: OcColors.accent,
              disabledColor: OcColors.accent.withAlpha(77),
              iconSize: 24,
            ),
          ],
        ),
      ),
    );
  }
}
