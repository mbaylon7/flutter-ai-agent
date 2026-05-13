import 'dart:io';

// The gateway exempts only client.id == "openclaw-control-ui" from
// the webchat-cannot-patch-sessions check (rejectWebchatSessionMutation in
// server-methods). Advertising as Control UI is what lets us rename
// sessions (sessions.patch) so they don't all show "Untitled".
const openClawClientIdAndroid = 'openclaw-control-ui';
const openClawClientIdIos = 'openclaw-control-ui';
const openClawClientIdMacos = 'openclaw-control-ui';

const openClawScopes = <String>[
  'operator.admin',
  'operator.read',
  'operator.write',
  'operator.approvals',
  'operator.pairing',
];

String currentClientId() {
  if (Platform.isIOS) return openClawClientIdIos;
  if (Platform.isMacOS) return openClawClientIdMacos;
  return openClawClientIdAndroid;
}

Map<String, dynamic> buildConnectParams({
  required String instanceId,
  required String appVersion,
  required Map<String, dynamic> deviceProof,
  required String? token,
  required String? deviceToken,
  required String userAgent,
  required String locale,
}) {
  final auth = <String, dynamic>{};
  if (token != null) {
    auth['token'] = token;
    // Gateway is configured with auth.mode=password; the shared token doubles
    // as the gateway password. Send both so either resolver path accepts.
    auth['password'] = token;
  }
  if (deviceToken != null) auth['deviceToken'] = deviceToken;

  return {
    'minProtocol': 3,
    'maxProtocol': 3,
    'client': {
      'id': currentClientId(),
      'version': appVersion,
      'platform': Platform.operatingSystem,
      'mode': 'webchat',
      'instanceId': instanceId,
    },
    'role': 'operator',
    'scopes': openClawScopes,
    'device': deviceProof,
    'caps': const ['tool-events'],
    'auth': auth,
    'userAgent': userAgent,
    'locale': locale,
  };
}
