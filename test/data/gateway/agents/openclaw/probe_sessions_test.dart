@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/ids.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/connect_params.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/device_proof.dart';
import 'package:stt_tts/data/gateway/shared/device_identity.dart';
import 'package:stt_tts/data/gateway/shared/envelope_codec.dart';
import 'package:stt_tts/data/gateway/shared/ws_connection.dart';
import 'package:stt_tts/data/secure/secure_store.dart';

void main() {
  final integration = Platform.environment['OPENCLAW_INTEGRATION'] == '1';
  final url = Platform.environment['OPENCLAW_URL'] ?? 'ws://127.0.0.1:18789/';
  final token = Platform.environment['OPENCLAW_TOKEN'] ?? 'test-123';

  test(
    'sessions.list against live gateway — what conversations exist?',
    () async {
      final identityMgr = DeviceIdentityManager(store: FakeSecureStore());
      final identity = await identityMgr.loadOrCreate();

      final wsUri = Uri.parse(url);
      final origin = 'http://${wsUri.authority}';
      final conn = WsConnection.connect(wsUri, headers: {'Origin': origin});
      final rpc = RpcChannel(conn, idGen: newRequestId);

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
      final params = buildConnectParams(
        instanceId: newInstanceId(),
        appVersion: '0.0.1',
        deviceProof: proof,
        token: token,
        deviceToken: null,
        userAgent: 'oc-probe/0.1',
        locale: 'en-US',
      );
      await rpc.request(method: 'connect', params: params);

      final res = await rpc.request(method: 'sessions.list', params: const {});
      // ignore: avoid_print
      print('========== sessions.list ==========');
      // ignore: avoid_print
      print(const JsonEncoder.withIndent('  ').convert(res));
      // ignore: avoid_print
      print('===================================');

      await rpc.close();
      await conn.close();
    },
    skip: integration ? null : 'set OPENCLAW_INTEGRATION=1',
    tags: ['integration'],
  );
}
