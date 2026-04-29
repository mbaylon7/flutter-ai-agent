import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/state/repositories_provider.dart';

/// Per-session message thread.  Keyed by [sessionKey].
///
/// On first subscription, kicks off a history load from the gateway (fire-and-
/// forget); the stream itself receives updates as they arrive via ChatRepository.
final messagesProvider =
    StreamProvider.family<List<Message>, String>((ref, sessionKey) {
  final repo = ref.watch(chatRepositoryProvider);
  // Trigger history load fire-and-forget; ChatRepository feeds the stream.
  unawaited(repo.loadHistory(sessionKey));
  return repo.messages(sessionKey);
});
