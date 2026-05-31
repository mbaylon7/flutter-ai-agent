import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/connection_config.dart';
import 'package:stt_tts/data/gateway/gateway_client.dart';
import 'package:stt_tts/data/secure/secure_store.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/domain/models/session.dart';
import 'package:stt_tts/state/connection_provider.dart';

class _FakeGatewayClient implements GatewayClient {
  bool shouldThrow = false;
  HelloResult? connectResult;
  ConnectionConfig? lastConnect;

  @override
  Future<HelloResult> connect(ConnectionConfig config) async {
    lastConnect = config;
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

Future<void> _settle(
  ProviderContainer container,
  bool Function(AgentConnection s) until,
) async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
    if (until(container.read(agentConnectionControllerProvider))) return;
  }
}

void main() {
  test('no stored creds → stays disconnected', () async {
    final secure = FakeSecureStore();
    final gw = _FakeGatewayClient();

    final container = ProviderContainer(
      overrides: [
        secureStoreProvider.overrideWithValue(secure),
        gatewayClientProvider.overrideWithValue(gw),
      ],
    );

    container.read(agentConnectionControllerProvider);
    // No work to do — stored creds are absent, so the controller short-circuits.
    await Future<void>.delayed(Duration.zero);

    final state = container.read(agentConnectionControllerProvider);
    container.dispose();

    expect(state.status, AgentConnectionStatus.disconnected);
    expect(gw.lastConnect, isNull);
  });

  test('stored deviceToken + connect succeeds → connected', () async {
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

    container.read(agentConnectionControllerProvider);
    await _settle(
      container,
      (s) => s.status != AgentConnectionStatus.connecting,
    );

    final state = container.read(agentConnectionControllerProvider);
    container.dispose();

    expect(state.status, AgentConnectionStatus.connected);
    expect(state.wsUrl, 'ws://localhost:18789/');
    expect(gw.lastConnect?.deviceToken, 'stored-device-token');
  });

  test('connect() with form inputs persists deviceToken', () async {
    final secure = FakeSecureStore();
    final gw = _FakeGatewayClient();

    final container = ProviderContainer(
      overrides: [
        secureStoreProvider.overrideWithValue(secure),
        gatewayClientProvider.overrideWithValue(gw),
      ],
    );

    final controller =
        container.read(agentConnectionControllerProvider.notifier);
    await controller.connect(
      url: '10.0.2.2',
      port: 18789,
      token: 'bootstrap-token',
    );

    final state = container.read(agentConnectionControllerProvider);
    expect(state.status, AgentConnectionStatus.connected);
    expect(state.wsUrl, 'ws://10.0.2.2:18789/');
    expect(await secure.read('oc.deviceToken'), 'new-dt');
    expect(await secure.read('oc.wsUrl'), 'ws://10.0.2.2:18789/');
    expect(gw.lastConnect?.token, 'bootstrap-token');
    container.dispose();
  });

  test('connect() failure surfaces friendly error', () async {
    final secure = FakeSecureStore();
    final gw = _FakeGatewayClient()..shouldThrow = true;

    final container = ProviderContainer(
      overrides: [
        secureStoreProvider.overrideWithValue(secure),
        gatewayClientProvider.overrideWithValue(gw),
      ],
    );

    final controller =
        container.read(agentConnectionControllerProvider.notifier);
    await controller.connect(
      url: 'agent.example.com',
      port: 18789,
      token: 'tok',
    );

    final state = container.read(agentConnectionControllerProvider);
    expect(state.status, AgentConnectionStatus.failed);
    expect(state.error, isNotNull);
    expect(state.error, isNot(contains('Exception')));
    container.dispose();
  });

  test('disconnect() clears persisted credentials', () async {
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

    final controller =
        container.read(agentConnectionControllerProvider.notifier);
    await _settle(
      container,
      (s) => s.status != AgentConnectionStatus.connecting,
    );

    await controller.disconnect();
    expect(await secure.read('oc.deviceToken'), isNull);
    expect(await secure.read('oc.wsUrl'), isNull);
    expect(
      container.read(agentConnectionControllerProvider).status,
      AgentConnectionStatus.disconnected,
    );
    container.dispose();
  });
}
