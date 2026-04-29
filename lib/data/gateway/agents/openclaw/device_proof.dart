import 'package:stt_tts/data/gateway/agents/openclaw/canonical.dart';
import 'package:stt_tts/data/gateway/shared/device_identity.dart';

/// Builds the `device` block sent inside the `connect` RPC params.
/// Returns the exact JSON shape the gateway expects.
Future<Map<String, dynamic>> buildDeviceProof({
  required DeviceIdentity identity,
  required String clientId,
  required String clientMode,
  required String role,
  required List<String> scopes,
  required String? token,
  required String nonce,
  DateTime? now,
}) async {
  final signedAtMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final canonical = buildCanonical(
    deviceId: identity.deviceId,
    clientId: clientId,
    clientMode: clientMode,
    role: role,
    scopes: scopes,
    signedAtMs: signedAtMs,
    token: token,
    nonce: nonce,
  );
  final signatureB64u = await identity.signCanonical(canonical);
  return {
    'id': identity.deviceId,
    'publicKey': identity.publicKeyB64u,
    'signature': signatureB64u,
    'signedAt': signedAtMs,
    'nonce': nonce,
  };
}
