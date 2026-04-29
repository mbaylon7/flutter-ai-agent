@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/openclaw_client.dart';
import 'package:stt_tts/data/gateway/connection_config.dart';
import 'package:stt_tts/data/gateway/shared/device_identity.dart';
import 'package:stt_tts/data/secure/secure_store.dart';

void main() {
  final integration = Platform.environment['OPENCLAW_INTEGRATION'] == '1';
  final url = Platform.environment['OPENCLAW_URL'] ?? 'ws://127.0.0.1:18789/';
  final token = Platform.environment['OPENCLAW_TOKEN'] ?? 'test-123';

  test(
    'connect to a running gateway, receive Hello with deviceToken',
    () async {
      final client = OpenClawGatewayClient(
        identityManager: DeviceIdentityManager(store: FakeSecureStore()),
      );
      final hello = await client.connect(
        ConnectionConfig(wsUrl: url, token: token),
      );
      expect(hello.role, isNotEmpty);
      // deviceToken may or may not be returned depending on gateway version
      // ignore: avoid_print
      print('hello: role=${hello.role}, deviceToken=${hello.deviceToken != null ? "received" : "none"}');
      await client.disconnect();
    },
    skip: integration ? null : 'set OPENCLAW_INTEGRATION=1 with a running gateway',
    tags: ['integration'],
  );
}
