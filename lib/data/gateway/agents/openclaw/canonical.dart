/// Builds the canonical signing string per the gateway's `nt()`.
/// Format: `v2|deviceId|clientId|clientMode|role|scopes,joined|signedAtMs|token|nonce`
/// (token segment is empty when null/missing).
String buildCanonical({
  required String deviceId,
  required String clientId,
  required String clientMode,
  required String role,
  required List<String> scopes,
  required int signedAtMs,
  required String? token,
  required String nonce,
}) {
  final scopesJoined = scopes.join(',');
  final tokenStr = token ?? '';
  return 'v2|$deviceId|$clientId|$clientMode|$role|$scopesJoined|$signedAtMs|$tokenStr|$nonce';
}
