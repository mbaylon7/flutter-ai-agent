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
