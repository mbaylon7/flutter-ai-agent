class ConnectionConfig {
  const ConnectionConfig({
    required this.wsUrl,
    this.token,
    this.deviceToken,
  });

  /// e.g. ws://192.168.1.10:18789/
  final String wsUrl;

  /// Shared gateway token. Used at first pair only; replaced by deviceToken.
  final String? token;

  /// Long-lived per-device token. Preferred when present.
  final String? deviceToken;
}
