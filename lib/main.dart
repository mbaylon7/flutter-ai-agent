import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/app.dart';
import 'package:stt_tts/data/cache/local_store.dart';
import 'package:stt_tts/state/repositories_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SqfliteLocalStore();
  await store.open();
  runApp(ProviderScope(
    overrides: [localStoreProvider.overrideWithValue(store)],
    child: const OpenClawApp(),
  ));
}
