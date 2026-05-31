import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/app.dart';
import 'package:stt_tts/core/trusted_hosts.dart';
import 'package:stt_tts/data/cache/local_store.dart';
import 'package:stt_tts/firebase_options.dart';
import 'package:stt_tts/state/repositories_provider.dart';

class _OpenClawHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      // Accept a self-signed cert ONLY for the agent host the user paired with.
      // The connect flow registers that host into [TrustedHosts]; nothing is
      // hardcoded. A CA-signed host never reaches this callback at all.
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) =>
              TrustedHosts.isAllowed(host);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
  HttpOverrides.global = _OpenClawHttpOverrides();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final store = SqfliteLocalStore();
  await store.open();
  runApp(ProviderScope(
    overrides: [localStoreProvider.overrideWithValue(store)],
    child: const OpenClawApp(),
  ));
}
