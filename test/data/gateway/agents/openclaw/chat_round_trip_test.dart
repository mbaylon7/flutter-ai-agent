@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/ids.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/openclaw_client.dart';
import 'package:stt_tts/data/gateway/connection_config.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/data/gateway/shared/device_identity.dart';
import 'package:stt_tts/data/secure/secure_store.dart';
import 'package:stt_tts/domain/models/message.dart';

void main() {
  final integration = Platform.environment['OPENCLAW_INTEGRATION'] == '1';
  final url = Platform.environment['OPENCLAW_URL'] ?? 'ws://127.0.0.1:18789/';
  final token = Platform.environment['OPENCLAW_TOKEN'];

  test(
    'OpenClawGatewayClient: connect → listSessions → sendMessage → stream → final',
    () async {
      final t = token;
      if (t == null || t.isEmpty) {
        markTestSkipped('Set OPENCLAW_TOKEN to run this integration test.');
        return;
      }
      final client = OpenClawGatewayClient(
        identityManager: DeviceIdentityManager(store: FakeSecureStore()),
      );
      await client.connect(ConnectionConfig(wsUrl: url, token: t));

      // 1) Sessions list works.
      final sessions = await client.listSessions();
      expect(sessions, isNotEmpty,
          reason: 'gateway should have at least the heartbeat session');
      final target = sessions.first;

      // ignore: avoid_print
      print('using session: ${target.key} ("${target.title}")');

      // 2) Subscribe to chat events BEFORE we send.
      final received = <ChatStreamEvent>[];
      final sub = client.watchChat().listen(received.add);

      // 3) Send a tiny message.
      final run = await client.sendMessage(
        sessionKey: target.key,
        text: 'Reply with one word: pong',
        idempotencyKey: newInstanceId(),
      );
      expect(run.runId, isNotEmpty);

      // 4) Wait for the final event (timeout safety).
      final finalEvent = await client
          .watchChat()
          .where((e) => e is ChatFinal && e.runId == run.runId)
          .cast<ChatFinal>()
          .first
          .timeout(const Duration(seconds: 15));

      expect(finalEvent.message.role, Role.assistant);
      expect(finalEvent.message.streaming, StreamingState.finalized);
      expect(finalEvent.message.visibleText.toLowerCase(), contains('pong'));

      // ignore: avoid_print
      print('final reply: "${finalEvent.message.visibleText}"');
      // ignore: avoid_print
      print('events received during run: ${received.length}');

      await sub.cancel();
      await client.disconnect();
    },
    skip: integration ? null : 'set OPENCLAW_INTEGRATION=1',
    tags: ['integration'],
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
