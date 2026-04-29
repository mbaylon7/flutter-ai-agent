import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/state/messages_provider.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:stt_tts/ui/chat/chat_composer.dart';
import 'package:stt_tts/ui/chat/message_bubble.dart';
import 'package:stt_tts/ui/chat/working_indicator.dart';

/// Full chat thread screen.
///
/// Watches [currentSessionProvider]:
/// - null  → "Pick a conversation" placeholder
/// - set   → message list (loading / error / data states) + composer
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Auto-scroll to the bottom (position 0 in a reversed list) whenever the
  /// widget rebuilds with a live message list.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessionKey = ref.watch(currentSessionProvider);

    if (sessionKey == null) {
      return const _EmptyPlaceholder();
    }

    return _SessionThread(
      sessionKey: sessionKey,
      scrollController: _scrollController,
      onScrollToBottom: _scrollToBottom,
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.chat_bubble_outline_rounded,
            color: OcColors.textMeta,
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            'Pick a conversation',
            style: TextStyle(
              color: OcColors.textSubtitle,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Swipe right to open the sessions drawer',
            style: TextStyle(
              color: OcColors.textMeta,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thread view for a known session key
// ---------------------------------------------------------------------------

class _SessionThread extends ConsumerWidget {
  const _SessionThread({
    required this.sessionKey,
    required this.scrollController,
    required this.onScrollToBottom,
  });

  final String sessionKey;
  final ScrollController scrollController;
  final VoidCallback onScrollToBottom;

  bool _showWorkingIndicator(List<Message> messages) {
    if (messages.isEmpty) return false;
    final last = messages.last;
    return last.role == Role.assistant &&
        last.streaming == StreamingState.partial &&
        last.parts.whereType<TextPart>().isEmpty;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(messagesProvider(sessionKey));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Couldn't load messages",
              style: TextStyle(color: OcColors.textSubtitle),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => ref.invalidate(messagesProvider(sessionKey)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (messages) {
        onScrollToBottom();
        final showWorking = _showWorkingIndicator(messages);

        // Determine the index of the last assistant message (for the Stop btn).
        final lastAssistantIdx = () {
          for (int i = messages.length - 1; i >= 0; i--) {
            if (messages[i].role == Role.assistant) return i;
          }
          return -1;
        }();

        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                reverse: true,
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  // reverse: true → index 0 = last message
                  final msg = messages[messages.length - 1 - index];
                  final msgIndex = messages.length - 1 - index;
                  return MessageBubble(
                    key: ValueKey(
                      '${msg.openclawId ?? msg.createdAt.microsecondsSinceEpoch}_$msgIndex',
                    ),
                    message: msg,
                    isLastAssistant: msgIndex == lastAssistantIdx,
                    allMessages: messages,
                  );
                },
              ),
            ),
            if (showWorking) const WorkingIndicator(),
            const ChatComposer(),
          ],
        );
      },
    );
  }
}
