import 'dart:io';

const openClawClientIdAndroid = 'openclaw-android';
const openClawClientIdIos = 'openclaw-ios';
const openClawClientIdMacos = 'openclaw-macos';

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
  if (token != null) auth['token'] = token;
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
