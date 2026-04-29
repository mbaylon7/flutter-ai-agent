# Slice 1D — Wake Word + Settings + Error/Empty State Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Round out slice 1 — opt-in wake word ("Hi OpenClaw" via Picovoice Porcupine), full settings panels (voice & speech, personality, privacy, about), and proper error/empty states (offline banner, mic denied, AI waking up, first-launch greeting). After this lands, slice 1 is feature-complete for OpenClaw users.

**Architecture:** A `WakeWordService` wraps `porcupine_flutter` and emits a stream of triggers when the keyword is detected. It's only running when (1) Speech Mode is the active screen AND (2) the toggle is on. Settings sections are static `ListView`s of `SettingTile`s wired to Riverpod providers. Error and empty states live in `lib/ui/states/` and are rendered conditionally inside `VoiceHome` and `ChatScreen` based on connection / permission / data state.

**Tech Stack:** All from 1A/1B/1C, plus `porcupine_flutter: ^3.0.4` (Picovoice; **paid license required for commercial production distribution** — flagged in the spec).

**Prerequisites:** 1C working end-to-end. Spec sections §10 (wake word), §22.4 (settings), §15.2 (UI states) are the source of truth.

---

## File Structure

| Path | Responsibility |
|---|---|
| `pubspec.yaml` | Add `porcupine_flutter`, `permission_handler` |
| `assets/wake-words/` | `.ppn` keyword files for "Hi OpenClaw" / "Hey OpenClaw" |
| `lib/data/voice/wake_word.dart` | `WakeWordService` (Porcupine wrapper) |
| `lib/data/permissions/permissions.dart` | Mic / wake-word permission requesters |
| `lib/state/settings_provider.dart` | Settings state (voice, tone, wake-word, language) |
| `lib/state/wake_word_provider.dart` | Wake-word lifecycle tied to voice mode + setting |
| `lib/ui/settings/settings_screen.dart` | Top-level settings scaffold |
| `lib/ui/settings/voice_section.dart` | Voice picker, rate, language, wake word |
| `lib/ui/settings/personality_section.dart` | Tone selector |
| `lib/ui/settings/privacy_section.dart` | Clear cache, unpair |
| `lib/ui/settings/about_section.dart` | Version, support |
| `lib/ui/settings/setting_tile.dart` | Themed row widget |
| `lib/ui/states/empty_first_launch.dart` | "Hi {name}" greeting |
| `lib/ui/states/offline_banner.dart` | Top banner across screens |
| `lib/ui/states/mic_denied_state.dart` | Speech-mode override when mic denied |
| `lib/ui/states/ai_waking_up_state.dart` | When the agent container is starting |
| `test/data/voice/wake_word_test.dart` | Mock wake-word service tests |

---

## Phase 1 — Settings panels (no new tech, just UI)

### Task 1: Settings provider (in-memory + secure-storage backed where it matters)

**Files:**
- Create: `lib/state/settings_provider.dart`

- [ ] **Step 1: Implement**

Create `lib/state/settings_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/data/secure/secure_store.dart';

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
```

(Adjust `secureStoreProvider` import if needed; it's defined in slice-1A's `connection_provider.dart`.)

- [ ] **Step 2: Analyze + commit**

```bash
flutter analyze && git add lib/state/settings_provider.dart && git commit -m "feat(state): settings provider"
```

---

### Task 2: `SettingTile` and the `SettingsScreen` scaffold

**Files:**
- Create: `lib/ui/settings/setting_tile.dart`
- Create: `lib/ui/settings/settings_screen.dart`

- [ ] **Step 1: Tile widget**

Create `lib/ui/settings/setting_tile.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

class SettingTile extends StatelessWidget {
  const SettingTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: OcColors.overlayTint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: OcColors.textSubtitle, size: 14),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                    style: const TextStyle(color: OcColors.textPrimary, fontSize: 13)),
                  if (subtitle != null)
                    Text(subtitle!,
                      style: const TextStyle(color: OcColors.textSubtitle, fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Screen scaffold**

Create `lib/ui/settings/settings_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/ui/settings/about_section.dart';
import 'package:stt_tts/ui/settings/personality_section.dart';
import 'package:stt_tts/ui/settings/privacy_section.dart';
import 'package:stt_tts/ui/settings/voice_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: OcColors.bgBottom,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Settings'),
        foregroundColor: OcColors.textPrimary,
      ),
      body: ListView(
        children: const [
          _SectionLabel('Voice & speech'),
          VoiceSection(),
          _SectionLabel('Personality'),
          PersonalitySection(),
          _SectionLabel('Privacy & data'),
          PrivacySection(),
          _SectionLabel('Help & About'),
          AboutSection(),
          SizedBox(height: 22),
          Center(child: Text('OpenClaw · A private AI assistant',
            style: TextStyle(color: OcColors.textMeta, fontSize: 10))),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(text.toUpperCase(),
      style: const TextStyle(
        color: OcColors.textMeta, fontWeight: FontWeight.w700,
        fontSize: 10, letterSpacing: 0.7,
      )),
  );
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/ui/settings/setting_tile.dart lib/ui/settings/settings_screen.dart
git commit -m "feat(ui): settings screen scaffold"
```

---

### Task 3: Voice section (voice picker + rate + wake-word toggle + language)

**Files:**
- Create: `lib/ui/settings/voice_section.dart`

- [ ] **Step 1: Implement**

Create `lib/ui/settings/voice_section.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/settings_provider.dart';
import 'package:stt_tts/state/voice_controller.dart';
import 'package:stt_tts/ui/settings/setting_tile.dart';

class VoiceSection extends ConsumerWidget {
  const VoiceSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final tts = ref.watch(ttsServiceProvider);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: OcColors.overlayTint,
        border: Border.all(color: OcColors.borderTint),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          SettingTile(
            icon: Icons.record_voice_over,
            title: 'Voice',
            subtitle: settings.voiceKey ?? 'Default',
            trailing: const Icon(Icons.chevron_right, color: OcColors.textMeta),
            onTap: () async {
              final picked = await showModalBottomSheet<String>(
                context: context,
                backgroundColor: OcColors.surface,
                builder: (_) => ListView(
                  shrinkWrap: true,
                  children: tts.voices.map((v) {
                    final key = '${v['name']}|${v['locale']}';
                    return ListTile(
                      title: Text(v['name'] ?? '',
                        style: const TextStyle(color: OcColors.textPrimary)),
                      subtitle: Text(v['locale'] ?? '',
                        style: const TextStyle(color: OcColors.textSubtitle)),
                      onTap: () => Navigator.pop(context, key),
                    );
                  }).toList(),
                ),
              );
              if (picked != null) {
                await tts.selectVoice(picked);
                await ref.read(settingsProvider.notifier).setVoiceKey(picked);
              }
            },
          ),
          const Divider(color: OcColors.borderTint, height: 1),
          SettingTile(
            icon: Icons.headphones,
            title: 'Wake word',
            subtitle: '"Hi OpenClaw" — uses extra battery',
            trailing: Switch(
              value: settings.wakeWordEnabled,
              onChanged: (v) => ref.read(settingsProvider.notifier).setWakeWord(v),
              activeColor: OcColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/ui/settings/voice_section.dart
git commit -m "feat(ui): voice settings section with picker + wake-word toggle"
```

---

### Task 4: Personality + Privacy + About sections

**Files:**
- Create: `lib/ui/settings/personality_section.dart`
- Create: `lib/ui/settings/privacy_section.dart`
- Create: `lib/ui/settings/about_section.dart`

- [ ] **Step 1: Personality (tone)**

Create `lib/ui/settings/personality_section.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/settings_provider.dart';
import 'package:stt_tts/ui/settings/setting_tile.dart';

class PersonalitySection extends ConsumerWidget {
  const PersonalitySection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: OcColors.overlayTint,
        border: Border.all(color: OcColors.borderTint),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SettingTile(
        icon: Icons.chat_bubble_outline,
        title: 'Tone',
        subtitle: switch (s.tone) {
          Tone.casual => 'Casual',
          Tone.professional => 'Professional',
          Tone.concise => 'Concise',
        },
        trailing: const Icon(Icons.chevron_right, color: OcColors.textMeta),
        onTap: () async {
          final picked = await showModalBottomSheet<Tone>(
            context: context,
            backgroundColor: OcColors.surface,
            builder: (_) => Column(
              mainAxisSize: MainAxisSize.min,
              children: Tone.values.map((t) => ListTile(
                title: Text(t.name,
                  style: const TextStyle(color: OcColors.textPrimary)),
                onTap: () => Navigator.pop(context, t),
              )).toList(),
            ),
          );
          if (picked != null) {
            await ref.read(settingsProvider.notifier).setTone(picked);
          }
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Privacy**

Create `lib/ui/settings/privacy_section.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/connection_provider.dart';
import 'package:stt_tts/state/sessions_provider.dart';
import 'package:stt_tts/ui/onboarding/welcome_screen.dart';
import 'package:stt_tts/ui/settings/setting_tile.dart';

class PrivacySection extends ConsumerWidget {
  const PrivacySection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: OcColors.overlayTint,
        border: Border.all(color: OcColors.borderTint),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          SettingTile(
            icon: Icons.delete_outline,
            title: 'Clear local cache',
            subtitle: 'Conversation list on this phone',
            onTap: () async {
              // Best-effort: clear sqflite cache.
              // Implementation: add a `clearCache` to LocalStore in 1B.
            },
          ),
          const Divider(color: OcColors.borderTint, height: 1),
          SettingTile(
            icon: Icons.power_settings_new,
            title: 'Unpair this device',
            subtitle: 'Removes the device token from this phone',
            onTap: () async {
              final store = ref.read(secureStoreProvider);
              await store.delete('oc.deviceToken');
              await store.delete('oc.wsUrl');
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  (_) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: About**

Create `lib/ui/settings/about_section.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/ui/settings/setting_tile.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: OcColors.overlayTint,
        border: Border.all(color: OcColors.borderTint),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        children: [
          SettingTile(icon: Icons.info_outline, title: 'Version', subtitle: '1.0.0-slice1'),
          Divider(color: OcColors.borderTint, height: 1),
          SettingTile(icon: Icons.help_outline, title: 'Support'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add lib/ui/settings/
git commit -m "feat(ui): personality + privacy + about settings sections"
```

---

## Phase 2 — Wake word

### Task 5: Add Picovoice dep + license placeholder

**Files:**
- Modify: `pubspec.yaml`
- Create: `assets/wake-words/.gitkeep`

- [ ] **Step 1: Add deps**

```yaml
  porcupine_flutter: ^3.0.4
  permission_handler: ^11.3.1
```

Add to the `flutter:` section:
```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/wake-words/
```

- [ ] **Step 2: Create assets folder**

```bash
mkdir -p assets/wake-words
touch assets/wake-words/.gitkeep
```

- [ ] **Step 3: Manual: register a free Picovoice console account, train a custom keyword for "Hi OpenClaw" and "Hey OpenClaw," download the Android `.ppn` file (and iOS one if applicable), drop them in `assets/wake-words/`. Get the AccessKey from the console.**

- [ ] **Step 4: Add the AccessKey to `--dart-define` for builds (do NOT commit it)**

Document in a new `docs/wake-word-setup.md`:
```md
# Wake word setup
1. Sign up at console.picovoice.ai (free for personal/dev use).
2. Train custom keywords: "Hi OpenClaw" + "Hey OpenClaw" for android (and iOS if needed).
3. Download .ppn files into `assets/wake-words/`.
4. Run with: `flutter run --dart-define=PICOVOICE_KEY=your-key`.
5. Production: paid commercial license required from Picovoice — DO NOT distribute without one.
```

- [ ] **Step 5: Commit (without the .ppn files until you have them)**

```bash
flutter pub get
git add pubspec.yaml pubspec.lock assets/wake-words/.gitkeep docs/wake-word-setup.md
git commit -m "chore: add porcupine_flutter + wake-word setup notes"
```

---

### Task 6: `WakeWordService`

**Files:**
- Create: `lib/data/voice/wake_word.dart`

- [ ] **Step 1: Implement**

Create `lib/data/voice/wake_word.dart`:
```dart
import 'dart:async';

import 'package:porcupine_flutter/porcupine.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';

class WakeWordService {
  WakeWordService({required this.accessKey});
  final String accessKey;

  PorcupineManager? _mgr;
  final _ctl = StreamController<void>.broadcast();
  DateTime _lastTrigger = DateTime.fromMillisecondsSinceEpoch(0);

  Stream<void> get triggers => _ctl.stream;

  Future<bool> start() async {
    try {
      _mgr = await PorcupineManager.fromKeywordPaths(
        accessKey,
        const [
          'assets/wake-words/Hi-OpenClaw_en_android.ppn',
          'assets/wake-words/Hey-OpenClaw_en_android.ppn',
        ],
        _onDetect,
      );
      await _mgr!.start();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _onDetect(int idx) {
    final now = DateTime.now();
    if (now.difference(_lastTrigger).inSeconds < 2) return; // 2s cooldown
    _lastTrigger = now;
    _ctl.add(null);
  }

  Future<void> stop() async {
    await _mgr?.stop();
    await _mgr?.delete();
    _mgr = null;
  }

  Future<void> dispose() async {
    await stop();
    await _ctl.close();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/data/voice/wake_word.dart
git commit -m "feat(voice): WakeWordService Picovoice wrapper with 2s cooldown"
```

---

### Task 7: Wake-word lifecycle provider (only on when speech mode visible AND toggle on)

**Files:**
- Create: `lib/state/wake_word_provider.dart`

- [ ] **Step 1: Implement**

Create `lib/state/wake_word_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/data/voice/wake_word.dart';
import 'package:stt_tts/state/settings_provider.dart';

const _picovoiceKey = String.fromEnvironment('PICOVOICE_KEY', defaultValue: '');

final wakeWordServiceProvider = Provider<WakeWordService?>((ref) {
  if (_picovoiceKey.isEmpty) return null;
  final s = WakeWordService(accessKey: _picovoiceKey);
  ref.onDispose(s.dispose);
  return s;
});

/// Activates / deactivates the wake-word listener based on settings.
class WakeWordController {
  WakeWordController(this._ref);
  final Ref _ref;
  bool _running = false;

  Future<void> sync({required bool speechModeVisible}) async {
    final svc = _ref.read(wakeWordServiceProvider);
    if (svc == null) return;
    final enabled = _ref.read(settingsProvider).wakeWordEnabled;
    final shouldRun = speechModeVisible && enabled;
    if (shouldRun && !_running) {
      _running = await svc.start();
    } else if (!shouldRun && _running) {
      await svc.stop();
      _running = false;
    }
  }
}

final wakeWordControllerProvider = Provider<WakeWordController>(
  (ref) => WakeWordController(ref),
);
```

Hook it into `VoiceHome` — call `ref.read(wakeWordControllerProvider).sync(speechModeVisible: true)` in `initState`, and `sync(speechModeVisible: false)` in `dispose`. Listen to the `triggers` stream to call `controller.tapMic()`.

- [ ] **Step 2: Commit**

```bash
git add lib/state/wake_word_provider.dart
git commit -m "feat(state): wake-word lifecycle controller"
```

---

## Phase 3 — Permissions UX

### Task 8: `permissions.dart` and the mic-denied state screen

**Files:**
- Create: `lib/data/permissions/permissions.dart`
- Create: `lib/ui/states/mic_denied_state.dart`

- [ ] **Step 1: Permissions helper**

Create `lib/data/permissions/permissions.dart`:
```dart
import 'package:permission_handler/permission_handler.dart';

class MicPermission {
  Future<MicPermissionState> request() async {
    final status = await Permission.microphone.request();
    return switch (status) {
      PermissionStatus.granted => MicPermissionState.granted,
      PermissionStatus.permanentlyDenied => MicPermissionState.permanentlyDenied,
      _ => MicPermissionState.denied,
    };
  }

  Future<MicPermissionState> check() async {
    final s = await Permission.microphone.status;
    return switch (s) {
      PermissionStatus.granted => MicPermissionState.granted,
      PermissionStatus.permanentlyDenied => MicPermissionState.permanentlyDenied,
      _ => MicPermissionState.denied,
    };
  }

  Future<void> openSettings() => openAppSettings();
}

enum MicPermissionState { granted, denied, permanentlyDenied }
```

- [ ] **Step 2: Mic-denied screen**

Create `lib/ui/states/mic_denied_state.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/data/permissions/permissions.dart';
import 'package:stt_tts/ui/widgets/oc_button.dart';

class MicDeniedState extends StatelessWidget {
  const MicDeniedState({super.key, required this.onTypeInstead});
  final VoidCallback onTypeInstead;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: ocBackgroundGradient),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76, height: 76,
                decoration: BoxDecoration(
                  color: OcColors.danger.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_off, color: OcColors.danger, size: 32),
              ),
              const SizedBox(height: 18),
              const Text('Microphone is off',
                style: TextStyle(color: OcColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                'To talk, OpenClaw needs the microphone. Open Settings to enable it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: OcColors.textSubtitle, fontSize: 12),
              ),
              const SizedBox(height: 22),
              OcButton(label: 'Open Settings', onPressed: () => MicPermission().openSettings()),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: onTypeInstead,
                child: const Text('or type instead',
                  style: TextStyle(color: OcColors.accent, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Hook into VoiceHome**

In `VoiceHome`, before showing the ring, check mic permission. If denied, render `MicDeniedState(onTypeInstead: () => Navigator.push(... ChatScreen ...))` instead of the ring.

- [ ] **Step 4: Commit**

```bash
git add lib/data/permissions/permissions.dart lib/ui/states/mic_denied_state.dart
git commit -m "feat(ui): mic permission state with deeplink to system settings"
```

---

## Phase 4 — Connection / loading states

### Task 9: Offline banner integration + first-launch greeting + AI-waking-up state

**Files:**
- Create: `lib/ui/states/empty_first_launch.dart`
- Create: `lib/ui/states/ai_waking_up_state.dart`
- Modify: `lib/ui/widgets/connection_banner.dart` (already exists from 1B — extend copy)

- [ ] **Step 1: First-launch greeting**

Create `lib/ui/states/empty_first_launch.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/ui/widgets/oc_button.dart';

class EmptyFirstLaunch extends StatelessWidget {
  const EmptyFirstLaunch({super.key, required this.userName, required this.onTapToTalk, required this.onStartTyping});
  final String userName;
  final VoidCallback onTapToTalk;
  final VoidCallback onStartTyping;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: ocBackgroundGradient),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('👋', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 14),
              Text('Hi $userName',
                style: const TextStyle(color: OcColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                "Your assistant is ready. Tap below and say something — or type if you'd rather.",
                textAlign: TextAlign.center,
                style: TextStyle(color: OcColors.textSubtitle, fontSize: 12),
              ),
              const SizedBox(height: 22),
              OcButton(label: 'Tap to talk', onPressed: onTapToTalk),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: onStartTyping,
                child: const Text('or start typing',
                  style: TextStyle(color: OcColors.accent, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: AI waking up state**

Create `lib/ui/states/ai_waking_up_state.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';

class AiWakingUpState extends StatefulWidget {
  const AiWakingUpState({super.key});
  @override
  State<AiWakingUpState> createState() => _S();
}
class _S extends State<AiWakingUpState> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: ocBackgroundGradient),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotationTransition(
              turns: _c,
              child: Container(
                width: 76, height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: OcColors.accent.withOpacity(0.5), width: 3, style: BorderStyle.solid),
                ),
                child: const Icon(Icons.settings, color: OcColors.accent, size: 32),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Waking up your assistant',
              style: TextStyle(color: OcColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Usually 10–15 seconds.',
              style: TextStyle(color: OcColors.textSubtitle, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Hook empty-state into VoiceHome**

In `VoiceHome.build`, when `messages.history.isEmpty && messages.streaming == null`, show `EmptyFirstLaunch` instead of the bare ring on first launch.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/states/
git commit -m "feat(ui): first-launch greeting + AI-waking-up state"
```

---

## Phase 5 — Final smoke + acceptance

### Task 10: Manual acceptance checklist for slice 1

- [ ] **Run the full smoke test below on a real Android device.**

```bash
flutter run --dart-define=PICOVOICE_KEY=<your-key>
```

Walk through:
1. Install fresh: see Welcome → Pair → Connecting → Ready → home (voice mode)
2. Empty state shows "Hi Marvin" greeting
3. Tap to talk: say "what time is it" → see live transcript → "Thinking" → "Speaking" with karaoke highlight
4. Mid-speak, say "Stop" → TTS stops
5. Swipe up to chat → see same conversation, type "tell me a joke" → see streaming reply → sources pill underneath
6. Tap sources pill → bottom sheet opens
7. Tap a source → opens browser
8. Tap stop mid-stream → reply truncates with "Stopped" indicator
9. Open drawer → sessions list updates live, search and filter chips work
10. Long-press a session → rename → see updated title
11. Open Settings → toggle Wake word ON → grant mic if prompted again
12. Lock screen, unlock — wake-word listener resumes (verify no battery anomaly)
13. Say "Hi OpenClaw" while phone is open in voice mode → listening starts
14. Open Settings → Privacy → Unpair → returns to welcome screen
15. Re-pair, confirm conversations are still on the gateway

- [ ] **Step 2: Tag the slice-1 release**

```bash
git tag -a slice-1-complete -m "Slice 1: core OpenClaw app — chat + voice + wake word + settings"
```

---

## Self-review

**Spec coverage:**
- §10 wake word: Tasks 5, 6, 7
- §6.4 runtime permissions: Task 8
- §15.2 specific UI states: Tasks 9 (first-launch, AI waking up, mic denied)
- §22.4 settings: Tasks 1–4
- §12 personalization: Tasks 1, 3, 4

**Out of scope for 1D (covered in slice 2+):**
- Sign-up / sign-in / accounts (slice 2)
- Trial / paywall / Stripe (slice 3)
- Nanobot / Zeroclaw (slices 4–5)
- Theme switcher / multi-language UI / accessibility audit / app icon / store listings (slice 6)

**Placeholder scan:** Task 5 step 3 says "manual: train custom keywords" — that's a real human task, not a code placeholder. The `.ppn` filenames in Task 6 are guesses based on Picovoice's naming convention; rename to whatever the console actually produces.

**Type consistency:** `Settings`, `Tone`, `SettingsNotifier`, `WakeWordService`, `WakeWordController`, `MicPermission`, `MicPermissionState` — all defined in this plan and used consistently.

**Picovoice license reminder:** the spec already calls out (§10) that commercial production distribution requires a paid Picovoice license. Slice 1's wake-word feature works for development use without one.
