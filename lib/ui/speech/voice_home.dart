import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/data/permissions/permissions.dart';
import 'package:stt_tts/data/voice/stt_service.dart';
import 'package:stt_tts/data/voice/tts_service.dart';
import 'package:stt_tts/state/settings_provider.dart';
import 'package:stt_tts/state/ui_mode_provider.dart';
import 'package:stt_tts/state/voice_controller.dart';
import 'package:stt_tts/state/voice_provider.dart';
import 'package:stt_tts/state/wake_word_provider.dart';
import 'package:stt_tts/ui/speech/state_ring.dart';
import 'package:stt_tts/ui/speech/transcript_strip.dart';
import 'package:stt_tts/ui/states/mic_denied_state.dart';
import 'package:stt_tts/ui/widgets/voice_visualizer.dart';

/// Voice-first home screen for one session.
///
/// - Mic ring (StateRing) at center, driven by VoiceStateMachine.
/// - Live partial transcript (listening) or karaoke subtitle (responding).
/// - Swipe up → ChatScreen for the same session.
class VoiceHome extends ConsumerStatefulWidget {
  const VoiceHome({super.key, required this.sessionKey});
  final String sessionKey;

  @override
  ConsumerState<VoiceHome> createState() => _VoiceHomeState();
}

class _VoiceHomeState extends ConsumerState<VoiceHome>
    with WidgetsBindingObserver {
  MicPermissionState? _micState; // null = not yet checked

  String _liveTranscript = '';
  String _spokenLine = '';
  int? _hlStart;
  int? _hlEnd;
  double _level = 0;

  StreamSubscription<SttTranscript>? _transcriptSub;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<TtsProgress>? _progressSub;
  StreamSubscription<TtsStatus>? _ttsStatusSub;
  StreamSubscription<void>? _wakeWordSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final stt = ref.read(sttServiceProvider);
    final tts = ref.read(ttsServiceProvider);

    _transcriptSub = stt.transcript.listen((t) {
      if (!mounted) return;
      setState(() => _liveTranscript = t.text);
    });

    _levelSub = stt.normalizedLevel.listen((l) {
      if (!mounted) return;
      setState(() => _level = l);
    });

    _progressSub = tts.progress.listen((p) {
      if (!mounted) return;
      setState(() {
        _spokenLine = p.text;
        _hlStart = p.wordStart;
        _hlEnd = p.wordEnd;
      });
    });

    _ttsStatusSub = tts.status.listen((s) {
      if (!mounted) return;
      if (s == TtsStatus.idle) {
        setState(() {
          _hlStart = null;
          _hlEnd = null;
        });
      }
    });

    // Wake word: sync lifecycle to the toggle, and route triggers to tapMic.
    final wakeCtrl = ref.read(wakeWordControllerProvider);
    unawaited(wakeCtrl.sync(speechModeVisible: true));
    final svc = ref.read(wakeWordServiceProvider);
    if (svc != null) {
      _wakeWordSub = svc.triggers.listen((_) {
        if (!mounted) return;
        final controller = ref.read(voiceControllerProvider(widget.sessionKey));
        controller.tapMic();
      });
    }
    // React to settings toggle changes while the screen is visible.
    ref.listenManual<bool>(
      settingsProvider.select((s) => s.wakeWordEnabled),
      (prev, next) => unawaited(wakeCtrl.sync(speechModeVisible: true)),
    );

    // Check mic permission so we can swap to MicDeniedState if needed.
    unawaited(_checkMic());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _transcriptSub?.cancel();
    _levelSub?.cancel();
    _progressSub?.cancel();
    _ttsStatusSub?.cancel();
    _wakeWordSub?.cancel();
    // Try to stop the wake-word listener. Wrapped in try/catch because the
    // ProviderScope may already be torn down (e.g. in widget tests), in
    // which case `ref.read` throws "Cannot use ref after disposed".
    try {
      final wakeCtrl = ref.read(wakeWordControllerProvider);
      unawaited(wakeCtrl.sync(speechModeVisible: false));
    } catch (_) {
      // Container is gone — nothing to clean up.
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkMic());
    }
  }

  Future<void> _checkMic() async {
    final s = await MicPermission().check();
    if (!mounted) return;
    setState(() => _micState = s);
  }

  String _statusLabel(VoiceState s) => switch (s) {
        VoiceState.idle => 'Tap to talk',
        VoiceState.listening => 'Listening…',
        VoiceState.processing => 'Thinking',
        VoiceState.responding => 'Speaking',
      };

  String _statusHint(VoiceState s) => switch (s) {
        VoiceState.idle => '',
        VoiceState.listening => 'Tap to stop',
        VoiceState.processing => '',
        VoiceState.responding => 'Tap to stop',
      };

  String _transcriptForState(VoiceState s) {
    switch (s) {
      case VoiceState.listening:
      case VoiceState.processing:
        return _liveTranscript;
      case VoiceState.responding:
        return _spokenLine;
      case VoiceState.idle:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final vstate = ref.watch(voiceStateProvider);
    final controller = ref.read(voiceControllerProvider(widget.sessionKey));

    if (_micState == MicPermissionState.denied ||
        _micState == MicPermissionState.permanentlyDenied) {
      return MicDeniedState(
        onTypeInstead: () =>
            ref.read(uiModeProvider.notifier).state = UiMode.chat,
      );
    }

    return Container(
      color: OcColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            StateRing(
              state: vstate,
              level: _level,
              onTap: controller.tapMic,
            ),
            const SizedBox(height: 16),
            Text(
              _statusLabel(vstate),
              style: const TextStyle(
                color: OcColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _statusHint(vstate),
              style: const TextStyle(
                  color: OcColors.textSubtitle, fontSize: 11),
            ),
            const SizedBox(height: 18),
            VoiceVisualizer(
              level: _level,
              active: vstate == VoiceState.listening ||
                  vstate == VoiceState.responding,
            ),
            const SizedBox(height: 12),
            TranscriptStrip(
              text: _transcriptForState(vstate),
              highlightStart:
                  vstate == VoiceState.responding ? _hlStart : null,
              highlightEnd: vstate == VoiceState.responding ? _hlEnd : null,
            ),
            const Spacer(flex: 2),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}
