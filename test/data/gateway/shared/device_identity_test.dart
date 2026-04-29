import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/shared/device_identity.dart';
import 'package:stt_tts/data/secure/secure_store.dart';

void main() {
  test('loadOrCreate generates once, returns same identity on second call',
      () async {
    final store = FakeSecureStore();
    final manager = DeviceIdentityManager(store: store);
    final a = await manager.loadOrCreate();
    final b = await manager.loadOrCreate();
    expect(a.deviceId, b.deviceId);
    expect(a.publicKeyB64u, b.publicKeyB64u);
    // deviceId is 64 lowercase hex chars (SHA-256 hex of publicKey)
    expect(a.deviceId, matches(RegExp(r'^[0-9a-f]{64}$')));
    // publicKey base64url-no-pad of 32 bytes ⇒ 43 chars, no '='
    expect(a.publicKeyB64u.length, 43);
    expect(a.publicKeyB64u.contains('='), false);
  });

  test('sign produces a 64-byte Ed25519 signature, base64url-no-pad',
      () async {
    final store = FakeSecureStore();
    final manager = DeviceIdentityManager(store: store);
    final id = await manager.loadOrCreate();
    final sigB64u = await id.signCanonical('hello world');
    // Ed25519 signature is exactly 64 bytes ⇒ 86 chars base64url-no-pad
    expect(sigB64u.length, 86);
    expect(sigB64u.contains('='), false);
  });

  test('base64UrlNoPad / decodeBase64UrlNoPad roundtrip', () {
    final bytes = List<int>.generate(32, (i) => i);
    final encoded = base64UrlNoPad(bytes);
    expect(encoded.contains('='), false);
    final decoded = decodeBase64UrlNoPad(encoded);
    expect(decoded, bytes);
  });

  test('hexLower produces 64-char lowercase hex for 32 bytes', () {
    final bytes = List<int>.generate(32, (i) => i);
    final h = hexLower(bytes);
    expect(h.length, 64);
    expect(h, h.toLowerCase());
    expect(h, matches(RegExp(r'^[0-9a-f]{64}$')));
  });
}
