import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:stt_tts/data/voice/tts_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/design_tokens.dart';
import 'package:stt_tts/data/permissions/permissions.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/state/messages_provider.dart';
import 'package:stt_tts/state/settings_provider.dart';
import 'package:stt_tts/state/theme_provider.dart';
import 'package:stt_tts/state/ui_mode_provider.dart';
import 'package:stt_tts/state/voice_controller.dart';
import 'package:stt_tts/state/voice_provider.dart';
import 'package:stt_tts/state/voice_session.dart';
import 'package:stt_tts/state/wake_word_provider.dart';
import 'package:stt_tts/ui/states/mic_denied_state.dart';
import 'package:stt_tts/ui/widgets/voice_visualizer.dart';

/// Per-session voice/chat body.
///
/// Layout matches `design/voice-app.html`:
///   • Wave stage fills the entire painter via `Positioned.fill`; the
///     wave equation anchors the curve to the bottom 50%.
///   • Chat stage (conversation list) overlays from `top: 64` to
///     `bottom: 135`.
class VoiceHome extends ConsumerStatefulWidget {
  const VoiceHome({super.key, required this.sessionKey});
  final String sessionKey;

  @override
  ConsumerState<VoiceHome> createState() => _VoiceHomeState();
}

class _VoiceHomeState extends ConsumerState<VoiceHome>
    with WidgetsBindingObserver {
  MicPermissionState? _micState;

  double _level = 0;
  final _scrollCtrl = ScrollController();

  StreamSubscription<double>? _levelSub;
  StreamSubscription<void>? _wakeWordSub;
  StreamSubscription<TtsStatus>? _ttsStatusSub;
  Timer? _ttsLevelTimer;
  final _ttsRng = math.Random();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final stt = ref.read(sttServiceProvider);

    _levelSub = stt.normalizedLevel.listen((l) {
      if (!mounted) return;
      setState(() => _level = l);
    });

    // Drive the visualizer when the AI is speaking. STT is stopped during
    // TTS playback, so its level stream goes silent — without this the wave
    // sits at its base "listening" amplitude with no motion while the AI
    // talks. Synthesizes a varying level pulsed at ~12 Hz.
    final tts = ref.read(ttsServiceProvider);
    _ttsStatusSub = tts.status.listen((s) {
      if (!mounted) return;
      if (s == TtsStatus.speaking) {
        _ttsLevelTimer?.cancel();
        _ttsLevelTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
          if (!mounted) return;
          setState(() => _level = 0.35 + _ttsRng.nextDouble() * 0.55);
        });
      } else {
        _ttsLevelTimer?.cancel();
        _ttsLevelTimer = null;
        setState(() => _level = 0);
      }
    });

    final wakeCtrl = ref.read(wakeWordControllerProvider);
    unawaited(wakeCtrl.sync(speechModeVisible: true));
    final svc = ref.read(wakeWordServiceProvider);
    if (svc != null) {
      _wakeWordSub = svc.triggers.listen((_) {
        if (!mounted) return;
        unawaited(
          ref.read(voiceSessionProvider(widget.sessionKey)).startListening(),
        );
      });
    }
    ref.listenManual<bool>(
      settingsProvider.select((s) => s.wakeWordEnabled),
      (prev, next) => unawaited(wakeCtrl.sync(speechModeVisible: true)),
    );

    unawaited(_checkMic());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _levelSub?.cancel();
    _wakeWordSub?.cancel();
    _ttsStatusSub?.cancel();
    _ttsLevelTimer?.cancel();
    _scrollCtrl.dispose();
    try {
      unawaited(ref.read(voiceSessionProvider(widget.sessionKey)).stop());
    } catch (_) {}
    try {
      ref.read(wakeWordControllerProvider).sync(speechModeVisible: false);
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkMic());
  }

  Future<void> _checkMic() async {
    final s = await MicPermission().check();
    if (!mounted) return;
    setState(() => _micState = s);
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(tokensProvider);
    final vstate = ref.watch(voiceStateProvider);
    final active = vstate == VoiceState.listening ||
        vstate == VoiceState.userSpeaking ||
        vstate == VoiceState.processing ||
        vstate == VoiceState.aiSpeaking ||
        vstate == VoiceState.responding;

    if (_micState == MicPermissionState.denied ||
        _micState == MicPermissionState.permanentlyDenied) {
      return MicDeniedState(
        onTypeInstead: () =>
            ref.read(uiModeProvider.notifier).state = UiMode.chat,
      );
    }

    final messagesAsync = ref.watch(messagesProvider(widget.sessionKey));
    final messages = messagesAsync.maybeWhen(
      data: (m) => m,
      orElse: () => const <Message>[],
    );

    final liveUserText = ref.watch(liveUserTranscriptProvider);
    final liveAiText = ref.watch(liveAiTranscriptProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Stack(
      children: [
        // Wave stage — full-screen behind everything; wave anchored to
        // bottom 40% of canvas.
        Positioned.fill(
          child: IgnorePointer(
            child: VoiceVisualizer(
              level: _level,
              active: active,
              bgColor: tokens.bg,
              silhouetteColor: tokens.silhouette,
              silhouetteOpacity: tokens.silhouetteOpacity,
              height: double.infinity,
            ),
          ),
        ),

        // Chat stage — top inset = safe-area + chatStageTop padding.
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.of(context).padding.top + OcLayout.chatStageTop,
          bottom: OcLayout.chatStageBottom,
          child: _Conversation(
            scrollCtrl: _scrollCtrl,
            messages: messages,
            liveUserText: (vstate == VoiceState.listening ||
                    vstate == VoiceState.userSpeaking)
                ? liveUserText
                : '',
            liveAiText: (vstate == VoiceState.aiSpeaking ||
                    vstate == VoiceState.responding ||
                    vstate == VoiceState.processing)
                ? liveAiText
                : '',
            state: vstate,
            tokens: tokens,
          ),
        ),
      ],
    );
  }
}

class _Conversation extends StatelessWidget {
  const _Conversation({
    required this.scrollCtrl,
    required this.messages,
    required this.liveUserText,
    required this.liveAiText,
    required this.state,
    required this.tokens,
  });

  final ScrollController scrollCtrl;
  final List<Message> messages;
  final String liveUserText;
  final String liveAiText;
  final VoiceState state;
  final OcTokens tokens;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    // While the AI is streaming, suppress the in-progress assistant
    // message from the committed list — the live subtitle handles it.
    final hideLastAssistant = liveAiText.isNotEmpty;
    Message? lastAssistant;
    if (hideLastAssistant) {
      for (var i = messages.length - 1; i >= 0; i--) {
        if (messages[i].role == Role.assistant) {
          lastAssistant = messages[i];
          break;
        }
      }
    }

    for (final m in messages) {
      if (m.role != Role.user && m.role != Role.assistant) continue;
      if (identical(m, lastAssistant)) continue;
      final text = m.visibleText.trim();
      if (text.isEmpty) continue;
      items.add(_MessageBlock(
        label: m.role == Role.user ? 'YOU' : 'AI',
        text: text,
        accent: m.role == Role.user,
        tokens: tokens,
      ));
    }
    if (liveUserText.isNotEmpty) {
      items.add(_MessageBlock(
        label: 'YOU',
        text: liveUserText,
        accent: true,
        muted: true,
        tokens: tokens,
      ));
    }
    if (liveAiText.isNotEmpty) {
      items.add(_MessageBlock(
        label: 'AI',
        text: liveAiText,
        accent: false,
        muted: true,
        tokens: tokens,
      ));
    } else if (state == VoiceState.processing) {
      items.add(_MessageBlock(
        label: 'AI',
        text: '…',
        accent: false,
        muted: true,
        tokens: tokens,
      ));
    }

    return ShaderMask(
      // Swapped reach vs the HTML default — long fade at the top (22% of
      // height) so messages dissolve into the panel above, short fade at
      // the bottom (20 px) just before the controls.
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Colors.transparent,
          Colors.black,
          Colors.black,
          Colors.transparent,
        ],
        stops: [
          0.0,
          20 / rect.height,
          0.78,
          1.0,
        ],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: scrollCtrl,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 64),
        itemCount: items.length,
        itemBuilder: (_, i) => items[i],
      ),
    );
  }
}

class _MessageBlock extends StatelessWidget {
  const _MessageBlock({
    required this.label,
    required this.text,
    required this.accent,
    required this.tokens,
    this.muted = false,
  });

  final String label;
  final String text;
  final bool accent;
  final bool muted;
  final OcTokens tokens;

  @override
  Widget build(BuildContext context) {
    final labelColor = accent ? tokens.accent : tokens.textMuted;
    final bodyColor = muted ? tokens.textSoft : tokens.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.18 * 11,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              letterSpacing: -0.005 * 14,
              color: bodyColor,
            ),
          ),
        ],
      ),
    );
  }
}
