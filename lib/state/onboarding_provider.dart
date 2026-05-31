import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/state/auth_provider.dart';
import 'package:stt_tts/state/connection_provider.dart';

/// Secure-store key for the "user has completed onboarding" flag. Scoped per
/// Firebase uid so signing in as a different account re-shows onboarding.
String _onboardingKey(String uid) => 'oc.onboardingDone.$uid';

/// `true` when the current signed-in user has either tapped Connect (and
/// succeeded) or tapped Skip on the onboarding screen at least once.
///
/// Resolves to `false` when there is no signed-in user — the router shouldn't
/// reach this branch in that case, but defaulting to false keeps the UI safe.
final onboardingDoneProvider = FutureProvider<bool>((ref) async {
  final auth = ref.watch(authStateProvider);
  final user = auth.asData?.value;
  if (user == null) return false;
  final secure = ref.watch(secureStoreProvider);
  final v = await secure.read(_onboardingKey(user.uid));
  return v == 'true';
});

extension OnboardingPersistence on Ref {
  Future<void> markOnboardingDone() async {
    final user = read(authServiceProvider).currentUser;
    if (user == null) return;
    await read(secureStoreProvider).write(_onboardingKey(user.uid), 'true');
    invalidate(onboardingDoneProvider);
  }

  Future<void> clearOnboardingDone(User? user) async {
    if (user == null) return;
    await read(secureStoreProvider).delete(_onboardingKey(user.uid));
    invalidate(onboardingDoneProvider);
  }
}

extension OnboardingPersistenceWidget on WidgetRef {
  Future<void> markOnboardingDone() async {
    final user = read(authServiceProvider).currentUser;
    if (user == null) return;
    await read(secureStoreProvider).write(_onboardingKey(user.uid), 'true');
    invalidate(onboardingDoneProvider);
  }

  Future<void> clearOnboardingDone(User? user) async {
    if (user == null) return;
    await read(secureStoreProvider).delete(_onboardingKey(user.uid));
    invalidate(onboardingDoneProvider);
  }
}
