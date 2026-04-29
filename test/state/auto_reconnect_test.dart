import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/connection_config.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/data/secure/secure_store.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/state/connection_provider.dart';

// ---------------------------------------------------------------------------
// Fake GatewayClient for auto-reconnect tests.
// ---------------------------------------------------------------------------

class _FakeGatewayClient implements GatewayClient {
  bool shouldThrow = false;
  HelloResult? connectResult;

  @override
  Future<HelloResult> connect(ConnectionConfig config) async {
    if (shouldThrow) throw Exception('connection refused');
    return connectResult ??
        const HelloResult(deviceToken: 'new-dt', role: 'user', scopes: []);
  }

  @override
  Future<void> disconnect() async {}

  @override
  Stream<ConnectionState> get connectionState =>
      const Stream<ConnectionState>.empty();

  @override
  GatewayCapabilities get capabilities =>
      const GatewayCapabilities(streaming: true, sources: false, plugins: false);

  @override
  Future<List<Session>> listSessions() async => [];

  @override
  Stream<Session> watchSessionUpdates() => const Stream.empty();

  @override
  Future<void> patchSession(String sessionKey, {String? title}) async {}

  @override
  Future<void> deleteSession(String sessionKey) async {}

  @override
  Future<List<Message>> loadHistory(String sessionKey) async => [];

  @override
  Future<ChatRun> sendMessage({
    required String sessionKey,
    required String text,
    required String idempotencyKey,
  }) =>
      throw UnimplementedError();

  @override
  Stream<ChatStreamEvent> watchChat() => const Stream.empty();

  @override
  Future<void> abort(String runId) async {}
}

// Pump microtasks until the condition is met or a max iteration count is hit.
Future<void> _settle(ProviderContainer container, StateNotifierProvider<AutoReconnectController, AsyncValue<bool>> provider) async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
    final s = container.read(provider);
    if (!s.isLoading) return;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Test 1: No deviceToken → state becomes AsyncValue.data(false).
  // -------------------------------------------------------------------------
  test('No deviceToken → state becomes data(false)', () async {
    final secure = FakeSecureStore(); // empty — no stored tokens
    final gw = _FakeGatewayClient();

    final container = ProviderContainer(
      overrides: [
        secureStoreProvider.overrideWithValue(secure),
        gatewayClientProvider.overrideWithValue(gw),
      ],
    );

    // Read the provider to initialise it, then wait for async to settle.
    container.read(autoReconnectControllerProvider);
    await _settle(container, autoReconnectControllerProvider);

    final state = container.read(autoReconnectControllerProvider);
    container.dispose();

    expect(state, const AsyncValue<bool>.data(false));
  });

  // -------------------------------------------------------------------------
  // Test 2: deviceToken present + gateway connect succeeds → data(true).
  // -------------------------------------------------------------------------
  test('deviceToken present + connect succeeds → state becomes data(true)',
      () async {
    final secure = FakeSecureStore();
    await secure.write('oc.deviceToken', 'stored-device-token');
    await secure.write('oc.wsUrl', 'ws://localhost:18789/');

    final gw = _FakeGatewayClient();

    final container = ProviderContainer(
      overrides: [
        secureStoreProvider.overrideWithValue(secure),
        gatewayClientProvider.overrideWithValue(gw),
      ],
    );

    container.read(autoReconnectControllerProvider);
    await _settle(container, autoReconnectControllerProvider);

    final state = container.read(autoReconnectControllerProvider);
    container.dispose();

    expect(state, const AsyncValue<bool>.data(true));
  });
}
