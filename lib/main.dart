import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/app.dart';
import 'package:stt_tts/data/cache/local_store.dart';
import 'package:stt_tts/state/repositories_provider.dart';

class _OpenClawHttpOverrides extends HttpOverrides {
  static const _trustedHosts = {'178.104.222.39'};

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) =>
              _trustedHosts.contains(host);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
  HttpOverrides.global = _OpenClawHttpOverrides();
  final store = SqfliteLocalStore();
  await store.open();
  runApp(ProviderScope(
    overrides: [localStoreProvider.overrideWithValue(store)],
    child: const OpenClawApp(),
  ));
}
