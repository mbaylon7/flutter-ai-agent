import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/state/repositories_provider.dart';

/// A single chat message bubble.
///
/// [isLastAssistant] is true when this is the last assistant message in the
/// visible list — used to show the Stop button for in-flight runs.
class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isLastAssistant,
  });

  final Message message;
  final bool isLastAssistant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (message.role) {
      Role.user => _UserBubble(message: message),
      Role.assistant => _AssistantBubble(
          message: message,
          isLastAssistant: isLastAssistant,
          ref: ref,
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
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: OcColors.accent.withAlpha(51), // 20% alpha
            border: Border.all(color: OcColors.accent.withAlpha(128)),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(6),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(6),
            ),
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
  });

  final Message message;
  final bool isLastAssistant;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Align(
      key: const Key('bubble_align_assistant'),
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: OcColors.surface,
                border: Border.all(color: OcColors.borderTint),
                borderRadius: BorderRadius.circular(18),
              ),
              child: _BubbleBody(
                message: message,
                textColor: OcColors.textBody,
              ),
            ),
            // TODO(Task 8): sources pill goes here when toolCalls is non-empty
            const SizedBox.shrink(),
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
    // TODO(Task 7): swap in MarkdownRenderer for assistant role
    final text = message.visibleText;

    return switch (message.streaming) {
      StreamingState.partial => _PartialBody(text: text, textColor: textColor),
      StreamingState.failed => _FailedBody(text: text, textColor: textColor),
      StreamingState.finalized || StreamingState.none => Text(
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
  const _PartialBody({required this.text, required this.textColor});

  final String text;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (text.isNotEmpty)
          Flexible(
            child: Text(
              text,
              style: TextStyle(color: textColor, fontSize: 14, height: 1.45),
            ),
          ),
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
