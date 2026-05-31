import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/connection_error.dart';
import 'package:stt_tts/core/logger.dart';
import 'package:stt_tts/core/trusted_hosts.dart';
import 'package:stt_tts/data/gateway/agents/openclaw/openclaw_client.dart';
import 'package:stt_tts/data/gateway/connection_config.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/data/gateway/shared/device_identity.dart';
import 'package:stt_tts/data/secure/secure_store.dart';

final secureStoreProvider = Provider<SecureStore>((_) => FlutterSecureStore());

final deviceIdentityManagerProvider = Provider<DeviceIdentityManager>(
  (ref) => DeviceIdentityManager(store: ref.read(secureStoreProvider)),
);

final gatewayClientProvider = Provider<GatewayClient>(
  (ref) => OpenClawGatewayClient(
    identityManager: ref.read(deviceIdentityManagerProvider),
  ),
);

final connectionStateProvider = StreamProvider<ConnectionState>((ref) {
  return ref.watch(gatewayClientProvider).connectionState;
});

// ---------------------------------------------------------------------------
// AgentConnection — single source of truth for the gateway connection state
// the UI cares about. Replaces the old AutoReconnect/PairController split.
// ---------------------------------------------------------------------------

enum AgentConnectionStatus { disconnected, connecting, connected, failed }

class AgentConnection {
  const AgentConnection({
    required this.status,
    this.error,
    this.wsUrl,
  });

  final AgentConnectionStatus status;

  /// User-friendly error message when [status] == [AgentConnectionStatus.failed].
  final String? error;

  /// The wsUrl we are currently connected to (when status == connected).
  final String? wsUrl;

  bool get isConnected => status == AgentConnectionStatus.connected;
  bool get isBusy => status == AgentConnectionStatus.connecting;

  AgentConnection copyWith({
    AgentConnectionStatus? status,
    String? error,
    String? wsUrl,
  }) {
    return AgentConnection(
      status: status ?? this.status,
      error: error,
      wsUrl: wsUrl ?? this.wsUrl,
    );
  }

  static const disconnected = AgentConnection(
    status: AgentConnectionStatus.disconnected,
  );
}

class AgentConnectionController extends StateNotifier<AgentConnection> {
  AgentConnectionController(this._ref)
      : _log = Logger(tag: 'agent-conn'),
        super(AgentConnection.disconnected) {
    // Attempt a silent reconnect on launch if we have a persisted device token.
    // Never auto-pair from scratch — the user has to enter credentials.
    unawaited(_tryStoredReconnect());
  }

  final Ref _ref;
  final Logger _log;

  Future<void> _tryStoredReconnect() async {
    final secure = _ref.read(secureStoreProvider);
    final deviceToken = await secure.read('oc.deviceToken');
    final wsUrl = await secure.read('oc.wsUrl');
    if (deviceToken == null || wsUrl == null) return;
    if (!mounted) return;
    // Trust the paired host's cert (self-signed agents) before the handshake.
    TrustedHosts.allow(Uri.parse(wsUrl).host);
    state = state.copyWith(status: AgentConnectionStatus.connecting);
    try {
      await _ref.read(gatewayClientProvider).connect(
            ConnectionConfig(wsUrl: wsUrl, deviceToken: deviceToken),
          );
      if (!mounted) return;
      state = AgentConnection(
        status: AgentConnectionStatus.connected,
        wsUrl: wsUrl,
      );
    } catch (e, st) {
      _log.warn('stored-reconnect failed: $e\n$st');
      if (!mounted) return;
      // Don't surface as failure — user simply hasn't reconnected yet.
      state = AgentConnection.disconnected;
    }
  }

  /// Connect using credentials entered in the onboarding / settings form.
  Future<void> connect({
    required String url,
    required int port,
    required String token,
  }) async {
    final wsUrl = _buildWsUrl(url, port);
    // Trust the paired host's cert (self-signed agents) before the handshake.
    TrustedHosts.allow(Uri.parse(wsUrl).host);
    state = state.copyWith(
      status: AgentConnectionStatus.connecting,
      error: null,
    );
    final client = _ref.read(gatewayClientProvider);
    final secure = _ref.read(secureStoreProvider);
    try {
      final hello = await client.connect(
        ConnectionConfig(wsUrl: wsUrl, token: token),
      );
      if (hello.deviceToken != null) {
        await secure.write('oc.deviceToken', hello.deviceToken!);
        await secure.write('oc.wsUrl', wsUrl);
      }
      if (!mounted) return;
      state = AgentConnection(
        status: AgentConnectionStatus.connected,
        wsUrl: wsUrl,
      );
    } catch (e, st) {
      _log.warn('connect failed: $e\n$st');
      if (!mounted) return;
      state = AgentConnection(
        status: AgentConnectionStatus.failed,
        error: friendlyConnectionError(e),
      );
    }
  }

  /// Tear down the live connection and clear stored credentials so the next
  /// launch lands on the onboarding screen.
  Future<void> disconnect() async {
    final client = _ref.read(gatewayClientProvider);
    final secure = _ref.read(secureStoreProvider);
    try {
      await client.disconnect();
    } catch (e) {
      _log.warn('disconnect ignored error: $e');
    }
    await secure.delete('oc.deviceToken');
    await secure.delete('oc.wsUrl');
    if (!mounted) return;
    state = AgentConnection.disconnected;
  }

  /// Clear the in-memory failure state without reconnecting. Used by the
  /// settings/onboarding forms when the user edits inputs after an error.
  void clearError() {
    if (state.status == AgentConnectionStatus.failed) {
      state = state.copyWith(
        status: AgentConnectionStatus.disconnected,
        error: null,
      );
    }
  }
}

final agentConnectionControllerProvider =
    StateNotifierProvider<AgentConnectionController, AgentConnection>(
  (ref) => AgentConnectionController(ref),
);

/// True when we currently have a live gateway connection. Used by the chat
/// repository to decide whether to forward a message or short-circuit with
/// the "please connect" reply.
final isAgentConnectedProvider = Provider<bool>(
  (ref) => ref.watch(agentConnectionControllerProvider).isConnected,
);

// ---------------------------------------------------------------------------
// URL assembly — the form takes URL (with or without scheme) + Port and we
// assemble `wss://host:port/` (or ws:// for loopback / private LANs).
// ---------------------------------------------------------------------------

String _buildWsUrl(String rawUrl, int port) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('URL is required');
  }
  if (port <= 0 || port > 65535) {
    throw const FormatException('Port must be between 1 and 65535');
  }

  String scheme;
  String host;
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('wss://') ||
      lower.startsWith('ws://') ||
      lower.startsWith('https://') ||
      lower.startsWith('http://')) {
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || parsed.host.isEmpty) {
      throw const FormatException('Invalid URL');
    }
    switch (parsed.scheme) {
      case 'https':
        scheme = 'wss';
        break;
      case 'http':
        scheme = 'ws';
        break;
      case 'wss':
      case 'ws':
        scheme = parsed.scheme;
        break;
      default:
        throw const FormatException('Unsupported URL scheme');
    }
    host = parsed.host;
  } else {
    host = trimmed.split('/').first;
    if (host.isEmpty) {
      throw const FormatException('URL is missing a host');
    }
    scheme = _isLoopbackOrPrivate(host) ? 'ws' : 'wss';
  }
  return '$scheme://$host:$port/';
}

bool _isLoopbackOrPrivate(String host) {
  if (host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '10.0.2.2' ||
      host == '::1') {
    return true;
  }
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)$').firstMatch(host);
  if (m == null) return false;
  final a = int.parse(m.group(1)!);
  final b = int.parse(m.group(2)!);
  if (a == 10) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return false;
}
