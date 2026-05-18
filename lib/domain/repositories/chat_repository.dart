import 'dart:async';

import 'package:stt_tts/core/ids.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/domain/models/message.dart';

/// Owns the message-list state for one or more sessions.
///
/// ### Stream semantics (BehaviorSubject-style, without rxdart)
///
/// `messages(sessionKey)` is a cold stream backed by a direct observer table.
/// Each new subscription receives the current snapshot as its first event
/// (queued synchronously during `.listen()`, delivered on the next event-loop
/// turn), then receives every subsequent mutation on the next event-loop turn
/// after `_setList` is called.
///
/// Implementation: `_listeners` stores a map from `sessionKey` to a set of
/// `void Function(List<Message>)` callbacks registered via [messages].
/// `_setList` iterates the set and calls each callback synchronously — the
/// callbacks call `MultiStreamController.addSync` which queues the event for
/// delivery on the next event-loop iteration.  `messages()` uses `Stream.multi`
/// so the registration callback fires synchronously on `.listen()`.
///
/// ### Folding rules (protocol-capture §5.1)
///
/// - **ChatStarted**: ensure a placeholder exists for `runId`; no-op if
///   `send()` already inserted one.
/// - **ChatDelta**: REPLACE placeholder parts with event.message.parts
///   (cumulative — not appended); keep `streaming: partial`.
/// - **ChatFinal**: replace parts + openclawId; set `streaming: finalized`.
/// - **ChatEnded**: lifecycle only — no-op.
/// - **ChatFailed**: set `streaming: failed`; append
///   `TextPart('(failed: $reason)')`.
class ChatRepository {
  ChatRepository(this._gw) {
    // Subscribe once in the constructor; route by sessionKey.
    _chatSub = _gw.watchChat().listen(_handleEvent);
  }

  final GatewayClient _gw;

  /// `sessionKey` → current message list.
  final Map<String, List<Message>> _messages = {};

  /// `sessionKey` → set of active callbacks registered by `messages()`.
  ///
  /// Each callback corresponds to one active subscription.  Calling a callback
  /// delivers the current list synchronously to that subscription's onData.
  final Map<String, Set<void Function(List<Message>)>> _listeners = {};

  late final StreamSubscription<ChatStreamEvent> _chatSub;

  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Live message list for [sessionKey].
  ///
  /// Cold stream (BehaviorSubject semantics without rxdart): each new
  /// subscription gets the current snapshot as its first event, then every
  /// subsequent mutation.  Events are queued on `_setList` and delivered on
  /// the next event-loop turn.
  Stream<List<Message>> messages(String sessionKey) {
    // Use Stream.multi so the onListen callback fires synchronously when
    // .listen() is called.  We register a direct callback in _listeners;
    // _setList calls it synchronously for all active subscribers.
    return Stream<List<Message>>.multi((controller) {
      void dispatch(List<Message> list) {
        if (!controller.isClosed) controller.addSync(list);
      }

      // Register before emitting snapshot so no update is lost.
      _listeners.putIfAbsent(sessionKey, () => {}).add(dispatch);
      controller.onCancel = () => _listeners[sessionKey]?.remove(dispatch);

      // Emit snapshot synchronously via addSync.
      controller.addSync(List<Message>.unmodifiable(
        _messages[sessionKey] ?? const <Message>[],
      ));
    });
  }

  /// Load full history from the gateway, replacing the in-memory list.
  /// Idempotent — subsequent calls re-fetch.
  Future<void> loadHistory(String sessionKey) async {
    final history = await _gw.loadHistory(sessionKey);
    _setList(sessionKey, history);
  }

  /// Optimistically insert a user message + assistant placeholder, call
  /// [GatewayClient.sendMessage], and correlate subsequent streaming events.
  ///
  /// Returns the [ChatRun] from the gateway. **Throws** if the gateway send
  /// fails (the placeholder is marked failed first, then the exception
  /// propagates).
  Future<ChatRun> send({
    required String sessionKey,
    required String text,
  }) async {
    final now = DateTime.now();

    // Auto-title the session from the first user message (gateway has no
    // server-side titling, so without this every session shows "Untitled").
    final isFirstMessage = _listFor(sessionKey).isEmpty;

    // 1. User message (immediately finalized).
    final userMsg = Message(
      role: Role.user,
      parts: [TextPart(text)],
      createdAt: now,
      streaming: StreamingState.finalized,
    );

    // 2. Assistant placeholder (streaming: partial, no runId yet).
    final placeholder = Message(
      role: Role.assistant,
      parts: const [],
      createdAt: now,
      streaming: StreamingState.partial,
    );

    // 3. Append + emit (calls all registered listeners synchronously).
    final current = List<Message>.of(_listFor(sessionKey))
      ..add(userMsg)
      ..add(placeholder);
    _setList(sessionKey, current);

    // 4. Idempotency key.
    final idem = newRequestId();

    // 5-9. Call gateway; handle success or error.
    try {
      final run = await _gw.sendMessage(
        sessionKey: sessionKey,
        text: text,
        idempotencyKey: idem,
      );

      // 6. Update the placeholder with the real runId.
      _updatePlaceholderRunId(sessionKey, run.runId);

      if (isFirstMessage) {
        await _autoTitleSession(sessionKey, text);
      }

      return run;
    } catch (e) {
      // Mark the placeholder as failed, then rethrow so callers can detect
      // the failure synchronously.
      _markFailed(
        sessionKey: sessionKey,
        runId: null,
        reason: e.toString(),
        isOptimisticFailure: true,
        prefix: 'send failed',
      );
      rethrow;
    }
  }

  /// Phase 1 / sandbox echo path. Inserts a user message and a finalized
  /// assistant message with the same text — no gateway call, no LLM. Used
  /// while we validate the on-device STT/TTS pipeline before wiring the
  /// real AI flow back in.
  Future<void> sendEcho({
    required String sessionKey,
    required String text,
  }) async {
    final now = DateTime.now();
    final userMsg = Message(
      role: Role.user,
      parts: [TextPart(text)],
      createdAt: now,
      streaming: StreamingState.finalized,
    );
    final assistantMsg = Message(
      role: Role.assistant,
      parts: [TextPart(text)],
      createdAt: now.add(const Duration(milliseconds: 1)),
      runId: newRequestId(),
      streaming: StreamingState.finalized,
    );
    final current = List<Message>.of(_listFor(sessionKey))
      ..add(userMsg)
      ..add(assistantMsg);
    _setList(sessionKey, current);
  }

  /// Abort an in-flight run.
  Future<void> abort(String runId) => _gw.abort(runId);

  Future<void> _autoTitleSession(String sessionKey, String firstMessage) async {
    final title = deriveTitle(firstMessage);
    if (title.isEmpty) return;
    try {
      await _gw.patchSession(sessionKey, title: title);
    } catch (_) {
      // Best-effort — failures fall back to whatever the gateway emits.
    }
  }

  /// Derive a short title for a session from the user's first message.
  /// Public so the chat composer can use the same logic for optimistic upsert.
  static String deriveTitle(String text) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return '';
    const maxLen = 48;
    if (cleaned.length <= maxLen) return cleaned;
    final cut = cleaned.substring(0, maxLen);
    final lastSpace = cut.lastIndexOf(' ');
    final trimmed = lastSpace > 16 ? cut.substring(0, lastSpace) : cut;
    return '$trimmed…';
  }

  /// Release all resources. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _chatSub.cancel();
    _listeners.clear();
    _messages.clear();
  }

  // ---------------------------------------------------------------------------
  // Event handling
  // ---------------------------------------------------------------------------

  void _handleEvent(ChatStreamEvent event) {
    final sessionKey = event.sessionKey;
    final runId = event.runId;

    switch (event) {
      case ChatStarted():
        // Ensure a placeholder exists (defensive: `send()` normally inserts one
        // before events arrive, but guard against unusual ordering).
        final list = _listFor(sessionKey);
        final hasPlaceholder =
            list.any((m) => m.role == Role.assistant && m.runId == runId);
        if (!hasPlaceholder) {
          final placeholder = Message(
            role: Role.assistant,
            parts: const [],
            createdAt: DateTime.now(),
            streaming: StreamingState.partial,
            runId: runId,
          );
          _setList(sessionKey, [...list, placeholder]);
        }

      case ChatDelta(:final message):
        // REPLACE parts (cumulative from protocol), keep streaming: partial.
        _mutateByRunId(sessionKey, runId, (m) {
          return m.copyWith(
            parts: message.parts,
            streaming: StreamingState.partial,
          );
        });

      case ChatFinal(:final message):
        // Replace parts + openclawId, set finalized.
        _mutateByRunId(sessionKey, runId, (m) {
          return Message(
            role: m.role,
            parts: message.parts,
            createdAt: m.createdAt,
            streaming: StreamingState.finalized,
            openclawId: message.openclawId,
            runId: m.runId,
          );
        });

      case ChatEnded():
        // Lifecycle only — no-op.
        break;

      case ChatFailed(:final reason):
        _markFailed(sessionKey: sessionKey, runId: runId, reason: reason);
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  List<Message> _listFor(String sessionKey) =>
      _messages[sessionKey] ?? const <Message>[];

  /// Update the in-memory list and synchronously notify all active subscribers.
  void _setList(String sessionKey, List<Message> list) {
    _messages[sessionKey] = list;
    final subs = _listeners[sessionKey];
    if (subs == null || subs.isEmpty) return;
    final unmodifiable = List<Message>.unmodifiable(list);
    // Iterate over a copy to guard against concurrent modification if a
    // subscriber cancels inside its dispatch callback.
    for (final cb in List.of(subs)) {
      cb(unmodifiable);
    }
  }

  /// Update the last assistant placeholder that has no runId yet.
  void _updatePlaceholderRunId(String sessionKey, String runId) {
    final list = _listFor(sessionKey);
    final idx = _lastIndexWhere(
      list,
      (m) => m.role == Role.assistant && m.runId == null,
    );
    if (idx == -1) return;
    final updated = List<Message>.of(list);
    updated[idx] = updated[idx].copyWith(runId: runId);
    _setList(sessionKey, updated);
  }

  /// Mutate the message whose `runId` matches [runId] in [sessionKey]'s list.
  void _mutateByRunId(
    String sessionKey,
    String runId,
    Message Function(Message) updater,
  ) {
    final list = _listFor(sessionKey);
    final idx = list.indexWhere((m) => m.runId == runId);
    if (idx == -1) return;
    final updated = List<Message>.of(list);
    updated[idx] = updater(updated[idx]);
    _setList(sessionKey, updated);
  }

  /// Mark a message as failed, appending a failure TextPart.
  ///
  /// [prefix] controls the label inside the parentheses: `'(failed: …)'` by
  /// default, or `'(send failed: …)'` for optimistic-insert failures so
  /// caller-side and gateway-side failures are distinguishable in logs/UI.
  void _markFailed({
    required String sessionKey,
    required String? runId,
    required String reason,
    bool isOptimisticFailure = false,
    String prefix = 'failed',
  }) {
    final list = _listFor(sessionKey);

    final int idx;
    if (runId != null) {
      idx = list.indexWhere((m) => m.runId == runId);
    } else if (isOptimisticFailure) {
      // Find the last assistant placeholder with no runId.
      idx = _lastIndexWhere(
        list,
        (m) => m.role == Role.assistant && m.runId == null,
      );
    } else {
      idx = -1;
    }

    if (idx == -1) return;

    final msg = list[idx];
    final failureParts = [...msg.parts, TextPart('($prefix: $reason)')];

    final updated = List<Message>.of(list);
    updated[idx] = msg.copyWith(
      streaming: StreamingState.failed,
      parts: failureParts,
    );
    _setList(sessionKey, updated);
  }

  static int _lastIndexWhere<T>(List<T> list, bool Function(T) test) {
    for (int i = list.length - 1; i >= 0; i--) {
      if (test(list[i])) return i;
    }
    return -1;
  }
}
