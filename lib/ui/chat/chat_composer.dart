import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/design_tokens.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/domain/repositories/chat_repository.dart';
import 'package:stt_tts/state/repositories_provider.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:stt_tts/state/theme_provider.dart';
import 'package:uuid/uuid.dart';

/// Minimal chat input rendered at `bottom: 141` (see `OcLayout`).
///
/// The HTML keeps the real `<input>` invisible and renders a separate
/// `.chat-input-display` with a custom thick caret animation, so the caret
/// is always visible whether or not the field has focus. We mirror that
/// behaviour with a transparent TextField stacked under a typed-text +
/// caret display layer.
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({super.key});

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _text = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_text != _controller.text) {
        setState(() => _text = _controller.text);
      }
    });
    // Mirror the HTML which focuses the input ~220 ms after mode switch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 220), () {
        if (mounted) _focusNode.requestFocus();
      });
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
      // Phase 1: echo path — no LLM/gateway. Same UX as real send.
      await ref
          .read(chatRepositoryProvider)
          .sendEcho(sessionKey: key, text: text);
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
    final tokens = ref.watch(tokensProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _focusNode.requestFocus,
        child: SizedBox(
          height: 44, // min-height from `.chat-input-wrap`
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Transparent real TextField captures focus + key events.
              TextField(
                key: const Key('composer_text_field'),
                controller: _controller,
                focusNode: _focusNode,
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                cursorColor: Colors.transparent,
                style: const TextStyle(
                  color: Colors.transparent,
                  fontSize: 15,
                  height: 1.45,
                ),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              // Custom display: typed text + thicker blinking caret.
              IgnorePointer(
                child: _Display(text: _text, tokens: tokens),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Display extends StatelessWidget {
  const _Display({required this.text, required this.tokens});

  final String text;
  final OcTokens tokens;

  @override
  Widget build(BuildContext context) {
    // Inline the caret as a WidgetSpan inside the text run so it wraps with
    // the last character instead of sitting in the right edge of the row
    // when the text spills to a second line.
    final style = TextStyle(
      color: tokens.text,
      fontSize: 15,
      height: 1.45,
      letterSpacing: -0.005 * 15,
    );
    return RichText(
      textAlign: TextAlign.center,
      softWrap: true,
      overflow: TextOverflow.visible,
      text: TextSpan(
        style: style,
        children: [
          if (text.isNotEmpty) TextSpan(text: text),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _Caret(color: tokens.text),
          ),
        ],
      ),
    );
  }
}

/// Thick blinking caret. Square-wave blink at 1.1 s — matches the HTML
/// `@keyframes caret-blink`.
class _Caret extends StatefulWidget {
  const _Caret({required this.color});
  final Color color;

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final on = _ctrl.value < 0.5;
        return Opacity(opacity: on ? 0.95 : 0.0, child: child);
      },
      child: Container(
        width: 3,
        height: 15 * 1.05, // matches CSS `height: 1.05em` with em=15px
        margin: const EdgeInsets.only(left: 1),
        color: widget.color,
      ),
    );
  }
}
