import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/data/cache/local_store.dart';
import 'package:stt_tts/domain/repositories/chat_repository.dart';
import 'package:stt_tts/domain/repositories/session_repository.dart';
import 'package:stt_tts/state/connection_provider.dart';

// ---------------------------------------------------------------------------
// LocalStore — overridden in main() with the opened SqfliteLocalStore.
// ---------------------------------------------------------------------------

final localStoreProvider = Provider<LocalStore>((ref) {
  throw UnimplementedError('localStoreProvider must be overridden in main()');
});

// ---------------------------------------------------------------------------
// Repository providers
// ---------------------------------------------------------------------------

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(
    ref.watch(gatewayClientProvider),
    ref.watch(localStoreProvider),
  ),
);

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final repo = ChatRepository(
    ref.watch(gatewayClientProvider),
    isAgentConnected: () => ref.read(isAgentConnectedProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});
