@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/ids.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/connect_params.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/device_proof.dart';
import 'package:stt_tts/data/gateway/shared/device_identity.dart';
import 'package:stt_tts/data/gateway/shared/ws_connection.dart';
import 'package:stt_tts/data/secure/secure_store.dart';

void main() {
  final integration = Platform.environment['OPENCLAW_INTEGRATION'] == '1';
  final url = Platform.environment['OPENCLAW_URL'] ?? 'ws://127.0.0.1:18789/';
  final token = Platform.environment['OPENCLAW_TOKEN'] ?? 'test-123';

  test(
    'capture chat round-trip event shapes',
    () async {
      final identityMgr = DeviceIdentityManager(store: FakeSecureStore());
      final identity = await identityMgr.loadOrCreate();

      final wsUri = Uri.parse(url);
      final origin = 'http://${wsUri.authority}';
      final conn = WsConnection.connect(wsUri, headers: {'Origin': origin});

      // Capture EVERY event we see, log it.
      final allEvents = <Map<String, dynamic>>[];
      conn.frames.where((f) => f is EventFrame).cast<EventFrame>().listen((f) {
        allEvents.add({'event': f.event, 'payload': f.payload, 'seq': f.seq});
        // ignore: avoid_print
        print('◀ event: ${f.event} '
            'payload=${jsonEncode(f.payload).substring(0, jsonEncode(f.payload).length > 200 ? 200 : jsonEncode(f.payload).length)}');
      });

      final rpc = RpcChannel(conn, idGen: newRequestId);

      // Connect
      final challenge = await conn.frames
          .where((f) => f is EventFrame && f.event == 'connect.challenge')
          .cast<EventFrame>()
          .first;
      final nonce = challenge.payload['nonce'] as String;
      final proof = await buildDeviceProof(
        identity: identity,
        clientId: 'openclaw-android',
        clientMode: 'webchat',
        role: 'operator',
        scopes: openClawScopes,
        token: token,
        nonce: nonce,
      );
      await rpc.request(
        method: 'connect',
        params: buildConnectParams(
          instanceId: newInstanceId(),
          appVersion: '0.0.1',
          deviceProof: proof,
          token: token,
          deviceToken: null,
          userAgent: 'oc-probe/0.1',
          locale: 'en-US',
        ),
      );

      // ignore: avoid_print
      print('========== CONNECTED ==========');

      // Inspect existing sessions
      final list = await rpc.request(method: 'sessions.list', params: const {});
      // ignore: avoid_print
      print('sessions count: ${(list['sessions'] as List?)?.length}');
      final sessions = (list['sessions'] as List?) ?? [];
      String? targetSessionId;
      for (final s in sessions) {
        final m = s as Map;
        // ignore: avoid_print
        print('  session: id=${m['sessionId']} name=${m['displayName']} kind=${m['kind']}');
        // Pick the first non-heartbeat for chat.history probe
        if (m['displayName'] != 'heartbeat' && targetSessionId == null) {
          targetSessionId = m['sessionId'] as String?;
        }
      }
      targetSessionId ??= sessions.isNotEmpty
          ? (sessions.first as Map)['sessionId'] as String?
          : null;

      // Use the sessionKey of the first session (e.g. "agent:main:main")
      final sessionKey = sessions.isNotEmpty
          ? (sessions.first as Map)['key'] as String?
          : null;
      if (sessionKey != null) {
        // ignore: avoid_print
        print('--- chat.history for $sessionKey ---');
        try {
          final hist = await rpc.request(
            method: 'chat.history',
            params: {'sessionKey': sessionKey},
          );
          final s = const JsonEncoder.withIndent('  ').convert(hist);
          // ignore: avoid_print
          print(s.length > 3000 ? '${s.substring(0, 3000)}...[truncated]' : s);
        } catch (e) {
          // ignore: avoid_print
          print('chat.history threw: $e');
        }
      }

      // chat.send into the existing sessionKey
      // ignore: avoid_print
      print('========== chat.send ==========');
      try {
        final res = await rpc.request(
          method: 'chat.send',
          params: {
            'sessionKey': sessionKey,
            'message': 'Reply with one word: pong',
            'idempotencyKey': newInstanceId(),
          },
        );
        // ignore: avoid_print
        print('chat.send response: ${jsonEncode(res)}');
      } catch (e) {
        // ignore: avoid_print
        print('chat.send error: $e');
      }

      // Watch events for 8 seconds to catch the streaming reply
      // ignore: avoid_print
      print('========== watching events for 8s ==========');
      await Future.delayed(const Duration(seconds: 8));
      // ignore: avoid_print
      print('========== captured ${allEvents.length} events total ==========');

      await rpc.close();
      await conn.close();
    },
    skip: integration ? null : 'set OPENCLAW_INTEGRATION=1',
    tags: ['integration'],
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
