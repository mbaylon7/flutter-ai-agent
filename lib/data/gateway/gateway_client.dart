import 'dart:async';

import 'package:stt_tts/data/gateway/connection_config.dart';

enum ConnectionState { idle, connecting, authenticated, disconnected, failed }

class HelloResult {
  const HelloResult({
    required this.deviceToken,
    required this.role,
    required this.scopes,
  });
  final String? deviceToken;
  final String role;
  final List<String> scopes;
}

class GatewayCapabilities {
  const GatewayCapabilities({
    required this.streaming,
    required this.sources,
    required this.plugins,
  });
  final bool streaming;
  final bool sources;
  final bool plugins;
}

abstract class GatewayClient {
  /// Open the socket, authenticate, return Hello on success.
  Future<HelloResult> connect(ConnectionConfig config);

  /// Tear down. Idempotent.
  Future<void> disconnect();

  /// State stream for the UI.
  Stream<ConnectionState> get connectionState;

  GatewayCapabilities get capabilities;
}
