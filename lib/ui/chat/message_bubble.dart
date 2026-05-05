import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/state/repositories_provider.dart';
import 'package:stt_tts/ui/chat/markdown_renderer.dart';
import 'package:stt_tts/ui/chat/sources_pill.dart';
import 'package:stt_tts/ui/chat/sources_sheet.dart';

/// A single chat message bubble.
///
/// [isLastAssistant] is true when this is the last assistant message in the
/// visible list — used to show the Stop button for in-flight runs.
///
/// [allMessages] is the full ordered list for the current session, passed in
/// from ChatScreen so that the sources pill can find tool-result Messages that
/// follow this assistant message without re-watching the provider per bubble.
/// Defaults to empty (no pill rendered in tests that don't supply it).
class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isLastAssistant,
    this.allMessages = const [],
  });

  final Message message;
  final bool isLastAssistant;
  final List<Message> allMessages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (message.role) {
      Role.user => _UserBubble(message: message),
      Role.assistant => _AssistantBubble(
          message: message,
          isLastAssistant: isLastAssistant,
          ref: ref,
          allMessages: allMessages,
        ),
      Role.tool || Role.toolResult => _ToolLine(message: message),
      Role.system => _SystemLine(message: message),
    };
  }
}

// ---------------------------------------------------------------------------
// User bubble
// ---------------------------------------------------------------------------

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return Align(
      key: const Key('bubble_align_user'),
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: OcColors.surfaceMuted,
            borderRadius: BorderRadius.circular(22),
          ),
          child: _BubbleBody(
            message: message,
            textColor: OcColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Assistant bubble
// ---------------------------------------------------------------------------

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.message,
    required this.isLastAssistant,
    required this.ref,
    required this.allMessages,
  });

  final Message message;
  final bool isLastAssistant;
  final WidgetRef ref;
  final List<Message> allMessages;

  /// Walks forward from [msgIndex]+1 in [allMessages] collecting consecutive
  /// toolResult messages, then builds a map from toolCallId → Message.
  Map<String, Message> _buildResultsMap(int msgIndex) {
    final map = <String, Message>{};
    for (int i = msgIndex + 1; i < allMessages.length; i++) {
      final m = allMessages[i];
      if (m.role != Role.toolResult) break;
      if (m.toolCallId != null) map[m.toolCallId!] = m;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final toolCalls = message.toolCalls;

    // Find this message's index in allMessages so we can locate tool results.
    final msgIndex = allMessages.indexOf(message);
    final resultsByCallId =
        msgIndex >= 0 ? _buildResultsMap(msgIndex) : const <String, Message>{};

    return Align(
      key: const Key('bubble_align_assistant'),
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: _BubbleBody(
                message: message,
                textColor: OcColors.textBody,
              ),
            ),
            // Sources pill — shown when the assistant message has tool calls.
            if (toolCalls.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.only(left: 16, right: 12, bottom: 2),
                child: SourcesPill(
                  count: toolCalls.length,
                  onTap: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: OcColors.surface,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      builder: (_) => SourcesSheet(
                        calls: toolCalls,
                        resultsByCallId: resultsByCallId,
                      ),
                    );
                  },
                ),
              ),
            if (isLastAssistant &&
                message.streaming == StreamingState.partial &&
                message.runId != null)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: TextButton(
                  onPressed: () {
                    ref
                        .read(chatRepositoryProvider)
                        .abort(message.runId!);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: OcColors.danger,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Stop', style: TextStyle(fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tool / toolResult line (Task 8 replaces with sources pill)
// ---------------------------------------------------------------------------

class _ToolLine extends StatelessWidget {
  const _ToolLine({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Text(
        message.visibleText.isEmpty
            ? (message.toolName ?? 'tool call')
            : message.visibleText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: OcColors.textMeta,
          fontSize: 11,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// System line
// ---------------------------------------------------------------------------

class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        child: Text(
          message.visibleText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: OcColors.textMeta,
            fontSize: 11,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bubble body (text + streaming indicator)
// ---------------------------------------------------------------------------

class _BubbleBody extends StatelessWidget {
  const _BubbleBody({
    required this.message,
    required this.textColor,
  });

  final Message message;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final text = message.visibleText;

    // Assistant messages are rendered with OcMarkdown so that code blocks,
    // headings, bold/italic, links etc. display with proper formatting.
    // User / system / tool messages stay as plain Text (they are never
    // markdown-formatted by the user).
    final isAssistant = message.role == Role.assistant;

    return switch (message.streaming) {
      StreamingState.partial => _PartialBody(
          text: text,
          textColor: textColor,
          isAssistant: isAssistant,
        ),
      StreamingState.failed => _FailedBody(text: text, textColor: textColor),
      StreamingState.finalized || StreamingState.none => isAssistant
          ? OcMarkdown(text) // Task 7: use markdown renderer for assistant
          : Text(
              text,
              style: TextStyle(color: textColor, fontSize: 14, height: 1.45),
            ),
    };
  }
}

// ---------------------------------------------------------------------------
// Partial streaming body — text + animated dots
// ---------------------------------------------------------------------------

class _PartialBody extends StatelessWidget {
  const _PartialBody({
    required this.text,
    required this.textColor,
    this.isAssistant = false,
  });

  final String text;
  final Color textColor;
  final bool isAssistant;

  @override
  Widget build(BuildContext context) {
    // For assistant streaming content, use OcMarkdown so formatting renders
    // live as tokens arrive. The incomplete-fence guard in OcMarkdown handles
    // mid-block streaming gracefully.
    final body = text.isEmpty
        ? null
        : isAssistant
            ? OcMarkdown(text) // Task 7: markdown during streaming
            : Text(
                text,
                style: TextStyle(color: textColor, fontSize: 14, height: 1.45),
              );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (body != null) Flexible(child: body),
        const SizedBox(width: 4),
        const _StreamingDots(key: Key('streaming_dots')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Failed body — text + warning chip
// ---------------------------------------------------------------------------

class _FailedBody extends StatelessWidget {
  const _FailedBody({required this.text, required this.textColor});

  final String text;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (text.isNotEmpty)
          Text(
            text,
            style: TextStyle(color: textColor, fontSize: 14, height: 1.45),
          ),
        const SizedBox(height: 6),
        Container(
          key: const Key('failed_chip'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: OcColors.danger.withAlpha(26),
            border: Border.all(color: OcColors.danger.withAlpha(77)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 12, color: OcColors.danger),
              SizedBox(width: 4),
              Text(
                'failed',
                style: TextStyle(
                  color: OcColors.danger,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Animated streaming dots (three dots, wave-style)
// ---------------------------------------------------------------------------

class _StreamingDots extends StatefulWidget {
  const _StreamingDots({super.key});

  @override
  State<_StreamingDots> createState() => _StreamingDotsState();
}

class _StreamingDotsState extends State<_StreamingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each dot bounces at a 1/3-cycle offset.
            final phase = (_controller.value - i / 3.0) % 1.0;
            // sin gives a smooth up-down; clamp to [0,1]
            final t = math.sin(phase * math.pi).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Transform.translate(
                offset: Offset(0, -3 * t),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: OcColors.textMeta
                        .withAlpha((128 + (127 * t).round())),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
