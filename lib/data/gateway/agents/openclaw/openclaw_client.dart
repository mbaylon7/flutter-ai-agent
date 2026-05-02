import 'dart:async';

import 'package:stt_tts/core/ids.dart';
import 'package:stt_tts/core/logger.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/connect_params.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/device_proof.dart';
import 'package:stt_tts/data/gateway/connection_config.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/data/gateway/shared/device_identity.dart';
import 'package:stt_tts/data/gateway/shared/ws_connection.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/domain/models/session.dart';

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

    // The gateway enforces an Origin allowlist (gateway.controlUi.allowedOrigins).
    // Defaults are http://localhost:<port> and http://127.0.0.1:<port>.
    //
    // For loopback hosts and the Android-emulator host alias (10.0.2.2 → host's
    // 127.0.0.1), rewrite Origin to 127.0.0.1 so it lands inside the default
    // allowlist regardless of which name the client used to dial.
    //
    // For non-loopback hosts (real LAN / WAN), pass the URL's authority through
    // unchanged — the gateway operator must add that origin to allowedOrigins.
    final wsUri = Uri.parse(config.wsUrl);
    final originScheme = wsUri.scheme == 'wss' ? 'https' : 'http';
    const loopbackHosts = {'localhost', '127.0.0.1', '10.0.2.2'};
    final originAuthority = loopbackHosts.contains(wsUri.host)
        ? '127.0.0.1:${wsUri.port}'
        : wsUri.authority;
    final origin = '$originScheme://$originAuthority';
    final conn = WsConnection.connect(
      wsUri,
      log: _log,
      headers: {'Origin': origin},
    );
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
    await _chatStream.close();
    await _sessionStream.close();
    await _eventSub?.cancel();
    await _rpc?.close();
    await _conn?.close();
    _eventSub = null;
    _rpc = null;
    _conn = null;
  }

  // ===== Event routing =====

  StreamSubscription? _eventSub;
  final _chatStream = StreamController<ChatStreamEvent>.broadcast();
  final _sessionStream = StreamController<Session>.broadcast();

  void _ensureEventRouter() {
    if (_eventSub != null) return;
    _eventSub = _conn!.frames.listen((f) {
      if (f is! EventFrame) return;
      _routeEvent(f);
    });
  }

  void _routeEvent(EventFrame f) {
    final p = f.payload;
    switch (f.event) {
      case 'agent':
        // {runId, stream:"lifecycle", sessionKey, data:{phase:"start"|"end"}}
        if (p['stream'] == 'lifecycle') {
          final phase = (p['data'] as Map?)?['phase'];
          final runId = p['runId'] as String? ?? '';
          final sk = p['sessionKey'] as String? ?? '';
          if (phase == 'start') {
            _chatStream.add(ChatStarted(runId: runId, sessionKey: sk));
          } else if (phase == 'end') {
            _chatStream.add(ChatEnded(runId: runId, sessionKey: sk));
          }
        }
        // We ignore stream:"assistant" — the matching `chat` delta carries
        // the same content with the message wrapper.
        break;
      case 'chat':
        // {runId, sessionKey, state:"delta"|"final", message:{...}}
        final runId = p['runId'] as String? ?? '';
        final sk = p['sessionKey'] as String? ?? '';
        final state = p['state'] as String?;
        final msg = (p['message'] as Map?)?.cast<String, dynamic>();
        if (msg == null) break;
        final parsed = Message.fromJson(msg).copyWith(
          streaming: state == 'final'
              ? StreamingState.finalized
              : StreamingState.partial,
          runId: runId,
        );
        if (state == 'delta') {
          _chatStream.add(
            ChatDelta(runId: runId, sessionKey: sk, message: parsed),
          );
        } else if (state == 'final') {
          _chatStream.add(
            ChatFinal(runId: runId, sessionKey: sk, message: parsed),
          );
        }
        break;
      case 'sessions.changed':
      case 'session.added':
      case 'session.updated':
        final session = (p as Map?)?.cast<String, dynamic>();
        if (session != null && session['key'] != null) {
          _sessionStream.add(Session.fromJson(session));
        }
        break;
    }
  }

  // ===== Sessions =====

  @override
  Future<List<Session>> listSessions() async {
    _ensureEventRouter();
    final res = await _rpc!.request(
      method: 'sessions.list',
      params: const {},
    );
    final list = (res['sessions'] as List? ?? const []).cast<Map>();
    return list
        .map((m) => Session.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  @override
  Stream<Session> watchSessionUpdates() {
    _ensureEventRouter();
    return _sessionStream.stream;
  }

  @override
  Future<void> patchSession(String sessionKey, {String? title}) async {
    final params = <String, dynamic>{'sessionKey': sessionKey};
    if (title != null) params['displayName'] = title;
    await _rpc!.request(method: 'sessions.patch', params: params);
  }

  @override
  Future<void> deleteSession(String sessionKey) async {
    await _rpc!.request(
      method: 'sessions.delete',
      params: {'sessionKey': sessionKey},
    );
  }

  // ===== Chat =====

  @override
  Future<List<Message>> loadHistory(String sessionKey) async {
    _ensureEventRouter();
    final res = await _rpc!.request(
      method: 'chat.history',
      params: {'sessionKey': sessionKey},
    );
    final raw = (res['messages'] as List? ?? const []).cast<Map>();
    return raw
        .map((m) => Message.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  @override
  Future<ChatRun> sendMessage({
    required String sessionKey,
    required String text,
    required String idempotencyKey,
  }) async {
    _ensureEventRouter();
    final res = await _rpc!.request(
      method: 'chat.send',
      params: {
        'sessionKey': sessionKey,
        'message': text,
        'idempotencyKey': idempotencyKey,
      },
    );
    return ChatRun(
      runId: res['runId'] as String,
      sessionKey: sessionKey,
    );
  }

  @override
  Stream<ChatStreamEvent> watchChat() {
    _ensureEventRouter();
    return _chatStream.stream;
  }

  @override
  Future<void> abort(String runId) async {
    await _rpc!.request(method: 'chat.abort', params: {'runId': runId});
  }
}
