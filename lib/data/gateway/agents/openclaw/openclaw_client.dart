import 'dart:async';

import 'package:stt_tts/core/ids.dart';
import 'package:stt_tts/core/logger.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/connect_params.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/device_proof.dart';
import 'package:stt_tts/data/gateway/connection_config.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/data/gateway/shared/device_identity.dart';
import 'package:stt_tts/data/gateway/shared/ws_connection.dart';

class OpenClawGatewayClient implements GatewayClient {
  OpenClawGatewayClient({
    required DeviceIdentityManager identityManager,
    String appVersion = '0.1.0',
    String userAgent = 'OpenClaw-Mobile/0.1.0',
    String locale = 'en-US',
    Logger? log,
  })  : _identityManager = identityManager,
        _appVersion = appVersion,
        _userAgent = userAgent,
        _locale = locale,
        _log = log ?? Logger(tag: 'openclaw');

  final DeviceIdentityManager _identityManager;
  final String _appVersion;
  final String _userAgent;
  final String _locale;
  final Logger _log;

  final _state = StreamController<ConnectionState>.broadcast();
  WsConnection? _conn;
  RpcChannel? _rpc;

  String? _instanceId;

  @override
  Stream<ConnectionState> get connectionState => _state.stream;

  @override
  GatewayCapabilities get capabilities =>
      const GatewayCapabilities(streaming: true, sources: true, plugins: true);

  @override
  Future<HelloResult> connect(ConnectionConfig config) async {
    _state.add(ConnectionState.connecting);

    final identity = await _identityManager.loadOrCreate();
    _instanceId ??= newInstanceId();

    final conn = WsConnection.connect(Uri.parse(config.wsUrl), log: _log);
    _conn = conn;
    final rpc = RpcChannel(conn, idGen: newRequestId);
    _rpc = rpc;

    // Wait for connect.challenge
    final challenge = await conn.frames
        .where((f) => f is EventFrame && f.event == 'connect.challenge')
        .cast<EventFrame>()
        .first
        .timeout(const Duration(seconds: 10));

    final nonce = challenge.payload['nonce'] as String;
    _log.info('challenge received, nonce=$nonce');

    // Build the device proof — token only when no deviceToken yet.
    final tokenForProof =
        config.deviceToken == null ? config.token : null;
    final proof = await buildDeviceProof(
      identity: identity,
      clientId: currentClientId(),
      clientMode: 'webchat',
      role: 'operator',
      scopes: openClawScopes,
      token: tokenForProof,
      nonce: nonce,
    );

    final params = buildConnectParams(
      instanceId: _instanceId!,
      appVersion: _appVersion,
      deviceProof: proof,
      token: tokenForProof,
      deviceToken: config.deviceToken,
      userAgent: _userAgent,
      locale: _locale,
    );

    final hello = await rpc.request(method: 'connect', params: params);
    final auth = (hello['auth'] as Map?)?.cast<String, dynamic>();
    final result = HelloResult(
      deviceToken: auth?['deviceToken'] as String?,
      role: auth?['role'] as String? ?? 'operator',
      scopes: ((auth?['scopes'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
    );

    _state.add(ConnectionState.authenticated);
    _log.info(
      'authenticated. deviceToken returned: ${result.deviceToken != null}',
    );
    return result;
  }

  @override
  Future<void> disconnect() async {
    _state.add(ConnectionState.disconnected);
    await _rpc?.close();
    await _conn?.close();
    _rpc = null;
    _conn = null;
  }
}
