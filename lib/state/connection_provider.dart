import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class PairController extends StateNotifier<AsyncValue<HelloResult?>> {
  PairController(this._ref) : super(const AsyncValue.data(null));
  final Ref _ref;

  Future<void> pair({required String wsUrl, required String token}) async {
    state = const AsyncValue.loading();
    final client = _ref.read(gatewayClientProvider);
    final config = ConnectionConfig(wsUrl: wsUrl, token: token);
    try {
      final hello = await client.connect(config);
      // Persist deviceToken for next launch
      if (hello.deviceToken != null) {
        await _ref
            .read(secureStoreProvider)
            .write('oc.deviceToken', hello.deviceToken!);
        await _ref.read(secureStoreProvider).write('oc.wsUrl', wsUrl);
      }
      state = AsyncValue.data(hello);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final pairControllerProvider =
    StateNotifierProvider<PairController, AsyncValue<HelloResult?>>(
  (ref) => PairController(ref),
);

// ---------------------------------------------------------------------------
// AutoReconnectController — attempts to reconnect on launch using the
// persisted deviceToken.  State is AsyncValue<bool>:
//   loading  — attempt in flight
//   data(true)  — reconnect succeeded (connected)
//   data(false) — no stored deviceToken, need fresh pair
//   error(_)    — connect failed
// ---------------------------------------------------------------------------

// Hardcoded fallbacks used when no deviceToken is stored yet, so the app can
// auto-pair on first launch and jump straight to HomeShell. Tried in order;
// 10.0.2.2 is the Android emulator's loopback to the host machine.
const _kAutoPairWsUrls = <String>[
  'wss://178.104.222.39:18789/',
];
const _kAutoPairToken = 'c60074f7-c5fb-493b-a3a0-d6fe08d47a9a';

class AutoReconnectController extends StateNotifier<AsyncValue<bool>> {
  AutoReconnectController(this._ref) : super(const AsyncValue.loading()) {
    _attempt();
  }

  final Ref _ref;

  Future<void> _attempt() async {
    final secure = _ref.read(secureStoreProvider);
    final deviceToken = await secure.read('oc.deviceToken');
    final wsUrl = await secure.read('oc.wsUrl');

    if (!mounted) return;

    if (deviceToken != null && wsUrl != null) {
      try {
        await _ref.read(gatewayClientProvider).connect(
              ConnectionConfig(wsUrl: wsUrl, deviceToken: deviceToken),
            );
        if (!mounted) return;
        state = const AsyncValue.data(true);
        return;
      } catch (_) {
        // Fall through to fresh-pair attempt.
      }
    }

    // No stored token (or reconnect failed) → auto-pair with hardcoded creds,
    // trying each candidate URL in order.
    for (final url in _kAutoPairWsUrls) {
      try {
        final hello = await _ref.read(gatewayClientProvider).connect(
              ConnectionConfig(wsUrl: url, token: _kAutoPairToken),
            );
        if (hello.deviceToken != null) {
          await secure.write('oc.deviceToken', hello.deviceToken!);
          await secure.write('oc.wsUrl', url);
        }
        if (!mounted) return;
        state = const AsyncValue.data(true);
        return;
      } catch (_) {
        // Try next candidate URL.
      }
    }
    if (!mounted) return;
    // Don't surface an error UI — keep the loader visible and retry so the
    // app auto-pairs as soon as the gateway becomes reachable.
    state = const AsyncValue.loading();
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    unawaited(_attempt());
  }

  Future<void> retry() async {
    state = const AsyncValue.loading();
    await _attempt();
  }
}

final autoReconnectControllerProvider =
    StateNotifierProvider<AutoReconnectController, AsyncValue<bool>>(
  (ref) => AutoReconnectController(ref),
);
