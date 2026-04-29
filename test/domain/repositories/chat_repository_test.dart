import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/connection_config.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/domain/repositories/chat_repository.dart';

// ---------------------------------------------------------------------------
// FakeGatewayClient
// ---------------------------------------------------------------------------

class FakeGatewayClient implements GatewayClient {
  // Configurable responses.
  List<Message> historyResult = [];
  String nextRunId = 'run-1';
  String nextSessionKey = 's1';
  Exception? sendError;

  // Recorded calls.
  final List<({String sessionKey, String text, String idempotencyKey})>
      sendCalls = [];
  final List<String> abortCalls = [];

  final StreamController<ChatStreamEvent> events =
      StreamController<ChatStreamEvent>.broadcast();

  @override
  Future<List<Message>> loadHistory(String sessionKey) async => historyResult;

  @override
  Future<ChatRun> sendMessage({
    required String sessionKey,
    required String text,
    required String idempotencyKey,
  }) async {
    sendCalls.add((
      sessionKey: sessionKey,
      text: text,
      idempotencyKey: idempotencyKey,
    ));
    if (sendError != null) throw sendError!;
    return ChatRun(runId: nextRunId, sessionKey: nextSessionKey);
  }

  @override
  Stream<ChatStreamEvent> watchChat() => events.stream;

  @override
  Future<void> abort(String runId) async => abortCalls.add(runId);

  // --- Unimplemented stubs ---

  @override
  Future<HelloResult> connect(ConnectionConfig config) =>
      throw UnimplementedError();

  @override
  Future<void> disconnect() => throw UnimplementedError();

  @override
  Stream<ConnectionState> get connectionState => throw UnimplementedError();

  @override
  GatewayCapabilities get capabilities => throw UnimplementedError();

  @override
  Future<List<Session>> listSessions() => throw UnimplementedError();

  @override
  Stream<Session> watchSessionUpdates() => throw UnimplementedError();

  @override
  Future<void> patchSession(String sessionKey, {String? title}) =>
      throw UnimplementedError();

  @override
  Future<void> deleteSession(String sessionKey) => throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Message makeTextMessage({
  required Role role,
  required String text,
  StreamingState streaming = StreamingState.finalized,
  String? runId,
  String? openclawId,
}) =>
    Message(
      role: role,
      parts: [TextPart(text)],
      createdAt: DateTime(2026, 1, 1),
      streaming: streaming,
      runId: runId,
      openclawId: openclawId,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late FakeGatewayClient gw;
  late ChatRepository repo;

  setUp(() {
    gw = FakeGatewayClient();
    repo = ChatRepository(gw);
  });

  tearDown(() async {
    await repo.dispose();
  });

  // -------------------------------------------------------------------------
  // 1. History loads
  // -------------------------------------------------------------------------

  test('loadHistory: messages(s1) first emit equals gateway history', () async {
    gw.historyResult = [
      makeTextMessage(role: Role.user, text: 'Hello'),
      makeTextMessage(role: Role.assistant, text: 'Hi there'),
    ];

    await repo.loadHistory('s1');

    final list = await repo.messages('s1').first;
    expect(list, hasLength(2));
    expect((list[0].parts.first as TextPart).text, 'Hello');
    expect((list[1].parts.first as TextPart).text, 'Hi there');
  });

  // -------------------------------------------------------------------------
  // 2. Optimistic insert
  // -------------------------------------------------------------------------

  test(
    'send: emits [user(hi), assistant(empty,partial)] before streaming events',
    () async {
      gw.nextRunId = 'run-opt';
      gw.nextSessionKey = 's1';

      // Capture emits from messages stream.
      final emits = <List<Message>>[];
      final sub = repo.messages('s1').listen(emits.add);

      await repo.send(sessionKey: 's1', text: 'hi');
      // Pump the event loop to let pending stream events be delivered.
      // Stream.multi queues events to the timer/event queue, so one pump
      // is needed to flush them before inspecting emits.
      await Future.delayed(Duration.zero);

      // After send returns and the event loop has pumped, at minimum 2 emits
      // should have happened: (a) [user + placeholder], (b) [user + placeholder
      // with runId].  We just check the final state via the most recent emit.
      final latest = emits.last;
      expect(latest, hasLength(2));

      final user = latest[0];
      expect(user.role, Role.user);
      expect((user.parts.first as TextPart).text, 'hi');
      expect(user.streaming, StreamingState.finalized);

      final assistant = latest[1];
      expect(assistant.role, Role.assistant);
      expect(assistant.streaming, StreamingState.partial);
      expect(assistant.runId, 'run-opt');

      await sub.cancel();
    },
  );

  // -------------------------------------------------------------------------
  // 3. Delta replaces parts (not appends)
  // -------------------------------------------------------------------------

  test(
    'ChatDelta: second delta replaces parts — single TextPart, not appended',
    () async {
      gw.nextRunId = 'run-delta';
      gw.nextSessionKey = 's1';

      await repo.send(sessionKey: 's1', text: 'hi');

      // First delta
      gw.events.add(ChatDelta(
        runId: 'run-delta',
        sessionKey: 's1',
        message: makeTextMessage(
          role: Role.assistant,
          text: 'Hel',
          streaming: StreamingState.partial,
        ),
      ));
      await Future<void>.microtask(() {});

      // Second cumulative delta
      gw.events.add(ChatDelta(
        runId: 'run-delta',
        sessionKey: 's1',
        message: makeTextMessage(
          role: Role.assistant,
          text: 'Hello world',
          streaming: StreamingState.partial,
        ),
      ));
      await Future<void>.microtask(() {});
      // Give the stream a chance to process
      await Future<void>.delayed(Duration.zero);

      final list = await repo.messages('s1').first;
      final assistant = list.last;
      expect(assistant.parts, hasLength(1));
      expect((assistant.parts.first as TextPart).text, 'Hello world');
      expect(assistant.streaming, StreamingState.partial);
    },
  );

  // -------------------------------------------------------------------------
  // 4. ChatFinal transitions streaming state
  // -------------------------------------------------------------------------

  test(
    'ChatFinal: placeholder has streaming=finalized and replaced parts',
    () async {
      gw.nextRunId = 'run-final';
      gw.nextSessionKey = 's1';

      await repo.send(sessionKey: 's1', text: 'q');

      gw.events.add(ChatFinal(
        runId: 'run-final',
        sessionKey: 's1',
        message: makeTextMessage(
          role: Role.assistant,
          text: 'Hello!',
          streaming: StreamingState.finalized,
          openclawId: 'oc-1',
        ),
      ));
      await Future<void>.delayed(Duration.zero);

      final list = await repo.messages('s1').first;
      final assistant = list.last;
      expect(assistant.streaming, StreamingState.finalized);
      expect((assistant.parts.first as TextPart).text, 'Hello!');
      expect(assistant.openclawId, 'oc-1');
    },
  );

  // -------------------------------------------------------------------------
  // 5. ChatFailed event
  // -------------------------------------------------------------------------

  test(
    'ChatFailed: placeholder has streaming=failed and (failed:) TextPart',
    () async {
      gw.nextRunId = 'run-fail';
      gw.nextSessionKey = 's1';

      await repo.send(sessionKey: 's1', text: 'q');

      gw.events.add(ChatFailed(
        runId: 'run-fail',
        sessionKey: 's1',
        reason: 'timeout',
      ));
      await Future<void>.delayed(Duration.zero);

      final list = await repo.messages('s1').first;
      final assistant = list.last;
      expect(assistant.streaming, StreamingState.failed);
      final text = assistant.parts.whereType<TextPart>().first.text;
      expect(text, contains('timeout'));
    },
  );

  // -------------------------------------------------------------------------
  // 6. Cross-session isolation
  // -------------------------------------------------------------------------

  test('events for s2 do not mutate s1', () async {
    gw.nextRunId = 'run-s1';
    gw.nextSessionKey = 's1';
    await repo.send(sessionKey: 's1', text: 'hello from s1');

    // Push a delta for a completely different session/run.
    gw.events.add(ChatDelta(
      runId: 'run-s2',
      sessionKey: 's2',
      message: makeTextMessage(
        role: Role.assistant,
        text: 'S2 text',
        streaming: StreamingState.partial,
      ),
    ));
    await Future<void>.delayed(Duration.zero);

    final s1List = await repo.messages('s1').first;
    // s1 placeholder should still be empty parts (no text yet).
    final placeholder = s1List.last;
    expect(placeholder.runId, 'run-s1');
    expect(placeholder.parts, isEmpty);

    // s2 should be untouched (no list created unless we called loadHistory or
    // send for s2). The event for s2 should have been ignored (no placeholder).
  });

  // -------------------------------------------------------------------------
  // 7. Late subscriber gets current snapshot
  // -------------------------------------------------------------------------

  test('late subscriber gets current snapshot as first emit', () async {
    gw.nextRunId = 'run-snap';
    gw.nextSessionKey = 's1';

    await repo.send(sessionKey: 's1', text: 'snapshot test');

    // Subscribe AFTER send has already inserted messages.
    final list = await repo.messages('s1').first;
    expect(list, hasLength(2));
    expect(list[0].role, Role.user);
    expect(list[1].role, Role.assistant);
  });

  // -------------------------------------------------------------------------
  // 8. Abort delegates to gateway
  // -------------------------------------------------------------------------

  test('abort delegates to GatewayClient.abort(runId)', () async {
    await repo.abort('run-to-abort');
    expect(gw.abortCalls, equals(['run-to-abort']));
  });

  // -------------------------------------------------------------------------
  // 9. Send failure rethrows and marks placeholder as failed
  // -------------------------------------------------------------------------

  test('send failure: rethrows gateway exception and marks placeholder failed',
      () async {
    final error = Exception('network error');
    gw.sendError = error;

    // send() must throw the same exception the fake gateway threw.
    await expectLater(
      () => repo.send(sessionKey: 's1', text: 'failing'),
      throwsA(error),
    );

    // After catching the exception the placeholder must be marked failed with
    // a '(send failed: …)' TextPart so caller-side failures are distinguishable
    // from gateway-side ChatFailed events.
    final list = await repo.messages('s1').first;
    expect(list, hasLength(2));

    final assistant = list.last;
    expect(assistant.streaming, StreamingState.failed);
    final failText = assistant.parts.whereType<TextPart>().first.text;
    expect(failText, startsWith('(send failed:'));
    expect(failText, contains('network error'));
  });
}
