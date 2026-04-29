import 'dart:async';

import 'package:stt_tts/data/gateway/connection_config.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/domain/models/session.dart';

enum ConnectionState { idle, connecting, authenticated, disconnected, failed }

class HelloResult {
  const HelloResult({
    required this.deviceToken,
    required this.role,
    required this.scopes,
  });
  final String? deviceToken;
  final String role;
  final List<String> scopes;
}

class GatewayCapabilities {
  const GatewayCapabilities({
    required this.streaming,
    required this.sources,
    required this.plugins,
  });
  final bool streaming;
  final bool sources;
  final bool plugins;
}

/// One generation turn — what `chat.send` returns, what streaming events
/// arrive against, what we abort by id.
class ChatRun {
  const ChatRun({required this.runId, required this.sessionKey});
  final String runId;
  final String sessionKey;
}

/// Streaming chat events emitted to UI.
sealed class ChatStreamEvent {
  const ChatStreamEvent({required this.runId, required this.sessionKey});
  final String runId;
  final String sessionKey;
}

class ChatStarted extends ChatStreamEvent {
  const ChatStarted({required super.runId, required super.sessionKey});
}

class ChatDelta extends ChatStreamEvent {
  const ChatDelta({
    required super.runId,
    required super.sessionKey,
    required this.message,
  });

  /// The current (cumulative) assistant message at this delta tick.
  final Message message;
}

class ChatFinal extends ChatStreamEvent {
  const ChatFinal({
    required super.runId,
    required super.sessionKey,
    required this.message,
  });
  final Message message;
}

class ChatEnded extends ChatStreamEvent {
  const ChatEnded({required super.runId, required super.sessionKey});
}

class ChatFailed extends ChatStreamEvent {
  const ChatFailed({
    required super.runId,
    required super.sessionKey,
    required this.reason,
  });
  final String reason;
}

abstract class GatewayClient {
  /// Open the socket, authenticate, return Hello on success.
  Future<HelloResult> connect(ConnectionConfig config);

  /// Tear down. Idempotent.
  Future<void> disconnect();

  /// State stream for the UI.
  Stream<ConnectionState> get connectionState;

  GatewayCapabilities get capabilities;

  // ===== Sessions =====

  Future<List<Session>> listSessions();

  /// Live updates to the sessions list (additions, renames, removals).
  /// Caller should call this AFTER [connect] to start receiving events.
  Stream<Session> watchSessionUpdates();

  /// Rename or otherwise patch session metadata.
  Future<void> patchSession(String sessionKey, {String? title});

  Future<void> deleteSession(String sessionKey);

  // ===== Chat =====

  /// Load full history for a session.
  Future<List<Message>> loadHistory(String sessionKey);

  /// Send a new user message. Returns the [ChatRun] to correlate streaming.
  Future<ChatRun> sendMessage({
    required String sessionKey,
    required String text,
    required String idempotencyKey,
  });

  /// Streaming events for ALL active runs. Filter by `sessionKey` or `runId`.
  Stream<ChatStreamEvent> watchChat();

  /// Abort an in-flight run.
  Future<void> abort(String runId);
}
