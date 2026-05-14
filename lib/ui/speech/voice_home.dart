import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/data/permissions/permissions.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/state/messages_provider.dart';
import 'package:stt_tts/state/settings_provider.dart';
import 'package:stt_tts/state/ui_mode_provider.dart';
import 'package:stt_tts/state/voice_controller.dart';
import 'package:stt_tts/state/voice_provider.dart';
import 'package:stt_tts/state/voice_session.dart';
import 'package:stt_tts/state/wake_word_provider.dart';
import 'package:stt_tts/ui/states/mic_denied_state.dart';
import 'package:stt_tts/ui/widgets/voice_visualizer.dart';

/// Voice-first home screen for one session.
///
/// Layout (matches `design/draft-design.html`):
///   • Top ~40% — aurora visualization, no controls.
///   • Middle — scrollable YOU/AI conversation transcript, latest at bottom.
///   • Bottom — [menu] · [mic FAB] · [settings].
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final stt = ref.read(sttServiceProvider);

    _levelSub = stt.normalizedLevel.listen((l) {
      if (!mounted) return;
      setState(() => _level = l);
    });

    final wakeCtrl = ref.read(wakeWordControllerProvider);
    unawaited(wakeCtrl.sync(speechModeVisible: true));
    final svc = ref.read(wakeWordServiceProvider);
    if (svc != null) {
      _wakeWordSub = svc.triggers.listen((_) {
        if (!mounted) return;
        // Wake word resumes (or starts) STT listening.
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
    _scrollCtrl.dispose();
    // Stop any in-flight voice session when the widget tears down. Don't
    // hold the provider read past unmount because the ProviderScope may be
    // gone if we're navigating out of the app.
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

    // Full-screen aurora as a backdrop; conversation overlays on top. The
    // glow lives at the bottom of the screen (matching the design refs).
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: VoiceVisualizer(
              level: _level,
              active: active,
              height: double.infinity,
            ),
          ),
        ),
        Positioned.fill(
          child: SafeArea(
            top: false,
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
            ),
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
  });

  final ScrollController scrollCtrl;
  final List<Message> messages;
  final String liveUserText;
  final String liveAiText;
  final VoiceState state;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    // While the AI is streaming, hide the last (in-progress) assistant
    // message from the committed list and let the live subtitle render it
    // instead — otherwise we'd show the same text twice.
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
      ));
    }
    if (liveUserText.isNotEmpty) {
      items.add(_MessageBlock(
        label: 'YOU',
        text: liveUserText,
        accent: true,
        muted: true,
      ));
    }
    if (liveAiText.isNotEmpty) {
      items.add(_MessageBlock(
        label: 'AI',
        text: liveAiText,
        accent: false,
        muted: true,
      ));
    } else if (state == VoiceState.processing) {
      items.add(const _MessageBlock(
        label: 'AI',
        text: '…',
        accent: false,
        muted: true,
      ));
    }

    return Stack(
      children: [
        ListView.builder(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
          itemCount: items.length,
          itemBuilder: (_, i) => items[i],
        ),
        // Soft fade at top of conversation, per design.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 36,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF050608),
                    const Color(0xFF050608).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageBlock extends StatelessWidget {
  const _MessageBlock({
    required this.label,
    required this.text,
    required this.accent,
    this.muted = false,
  });

  final String label;
  final String text;
  final bool accent;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: accent
                  ? const Color(0xFF6E8CFF)
                  : Colors.white.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 16,
              height: 1.5,
              color: muted
                  ? Colors.white.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }
}

