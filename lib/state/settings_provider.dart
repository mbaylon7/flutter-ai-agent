import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/data/secure/secure_store.dart';
import 'package:stt_tts/state/connection_provider.dart' show secureStoreProvider;

enum Tone { casual, professional, concise }

class Settings {
  const Settings({
    required this.voiceKey,
    required this.tone,
    required this.wakeWordEnabled,
  });
  final String? voiceKey;
  final Tone tone;
  final bool wakeWordEnabled;

  Settings copyWith({String? voiceKey, Tone? tone, bool? wakeWordEnabled}) =>
      Settings(
        voiceKey: voiceKey ?? this.voiceKey,
        tone: tone ?? this.tone,
        wakeWordEnabled: wakeWordEnabled ?? this.wakeWordEnabled,
      );
}

class SettingsNotifier extends StateNotifier<Settings> {
  SettingsNotifier(this._store)
      : super(const Settings(voiceKey: null, tone: Tone.casual, wakeWordEnabled: false)) {
    _load();
  }
  final SecureStore _store;

  Future<void> _load() async {
    final v = await _store.read('oc.voiceKey');
    final t = await _store.read('oc.tone');
    final w = await _store.read('oc.wakeWord');
    state = state.copyWith(
      voiceKey: v,
      tone: switch (t) {
        'professional' => Tone.professional,
        'concise' => Tone.concise,
        _ => Tone.casual,
      },
      wakeWordEnabled: w == '1',
    );
  }

  Future<void> setVoiceKey(String k) async {
    state = state.copyWith(voiceKey: k);
    await _store.write('oc.voiceKey', k);
  }

  Future<void> setTone(Tone t) async {
    state = state.copyWith(tone: t);
    await _store.write('oc.tone', t.name);
  }

  Future<void> setWakeWord(bool v) async {
    state = state.copyWith(wakeWordEnabled: v);
    await _store.write('oc.wakeWord', v ? '1' : '0');
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, Settings>(
  (ref) => SettingsNotifier(ref.read(secureStoreProvider)),
);
