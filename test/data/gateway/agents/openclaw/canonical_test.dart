import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/canonical.dart';

void main() {
  test('canonical matches the captured connect request', () {
    final s = buildCanonical(
      deviceId:
          '759fe82249316fdc36e3f306ebacfe54b2e33e4a2a73772911c33c570cbc9934',
      clientId: 'openclaw-control-ui',
      clientMode: 'webchat',
      role: 'operator',
      scopes: const [
        'operator.admin',
        'operator.read',
        'operator.write',
        'operator.approvals',
        'operator.pairing',
      ],
      signedAtMs: 1777443641132,
      token: 'test-123',
      nonce: '4aafea19-095b-40e6-bd18-7d0739ee6c34',
    );
    expect(
      s,
      'v2|759fe82249316fdc36e3f306ebacfe54b2e33e4a2a73772911c33c570cbc9934'
      '|openclaw-control-ui|webchat|operator'
      '|operator.admin,operator.read,operator.write,operator.approvals,operator.pairing'
      '|1777443641132|test-123|4aafea19-095b-40e6-bd18-7d0739ee6c34',
    );
  });

  test('null token becomes empty segment', () {
    final s = buildCanonical(
      deviceId: 'D',
      clientId: 'C',
      clientMode: 'webchat',
      role: 'operator',
      scopes: const ['a'],
      signedAtMs: 1,
      token: null,
      nonce: 'N',
    );
    expect(s, 'v2|D|C|webchat|operator|a|1||N');
  });
}
