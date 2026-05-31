import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/device_proof.dart';
import 'package:stt_tts/data/gateway/shared/device_identity.dart';
import 'package:stt_tts/data/secure/secure_store.dart';

void main() {
  test('build returns the gateway-required device shape', () async {
    final id =
        await DeviceIdentityManager(store: FakeSecureStore()).loadOrCreate();
    final proof = await buildDeviceProof(
      identity: id,
      clientId: 'openclaw-android',
      clientMode: 'webchat',
      role: 'operator',
      scopes: const ['operator.admin'],
      token: 'dummy-fixture-token',
      nonce: 'NONCE',
      now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    expect(proof['id'], id.deviceId);
    expect(proof['publicKey'], id.publicKeyB64u);
    expect(proof['signature'], isA<String>());
    expect((proof['signature'] as String).length, 86);
    expect((proof['signature'] as String).contains('='), false);
    expect(proof['signedAt'], 1700000000000);
    expect(proof['nonce'], 'NONCE');
  });
}
