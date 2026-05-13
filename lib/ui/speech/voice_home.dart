import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/data/permissions/permissions.dart';
import 'package:stt_tts/data/voice/stt_service.dart';
import 'package:stt_tts/data/voice/tts_service.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:stt_tts/state/messages_provider.dart';
import 'package:stt_tts/state/settings_provider.dart';
import 'package:stt_tts/state/ui_mode_provider.dart';
import 'package:stt_tts/state/voice_controller.dart';
import 'package:stt_tts/state/voice_provider.dart';
import 'package:stt_tts/state/wake_word_provider.dart';
import 'package:stt_tts/ui/settings/settings_screen.dart';
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

  String _liveTranscript = '';
  String _spokenLine = '';
  double _level = 0;

  final _scrollCtrl = ScrollController();

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
      setState(() => _spokenLine = p.text);
    });

    _ttsStatusSub = tts.status.listen((s) {
      if (!mounted) return;
      if (s == TtsStatus.idle) setState(() {});
    });

    final wakeCtrl = ref.read(wakeWordControllerProvider);
    unawaited(wakeCtrl.sync(speechModeVisible: true));
    final svc = ref.read(wakeWordServiceProvider);
    if (svc != null) {
      _wakeWordSub = svc.triggers.listen((_) {
        if (!mounted) return;
        ref.read(voiceControllerProvider(widget.sessionKey)).tapMic();
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
    _transcriptSub?.cancel();
    _levelSub?.cancel();
    _progressSub?.cancel();
    _ttsStatusSub?.cancel();
    _wakeWordSub?.cancel();
    _scrollCtrl.dispose();
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
    final controller = ref.read(voiceControllerProvider(widget.sessionKey));
    final active = vstate == VoiceState.listening ||
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

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Container(
      color: OcColors.surface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Aurora region — design calls for top region with no overlay.
            Expanded(
              flex: 4,
              child: IgnorePointer(
                child: VoiceVisualizer(
                  level: _level,
                  active: active,
                  height: double.infinity,
                ),
              ),
            ),
            // Conversation transcript.
            Expanded(
              flex: 6,
              child: _Conversation(
                scrollCtrl: _scrollCtrl,
                messages: messages,
                liveUserText: vstate == VoiceState.listening ||
                        vstate == VoiceState.processing
                    ? _liveTranscript
                    : '',
                liveAiText:
                    vstate == VoiceState.responding ? _spokenLine : '',
              ),
            ),
            _BottomBar(
              active: active,
              onMic: controller.tapMic,
              onMenu: () => Scaffold.of(context).openDrawer(),
              onSettings: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Conversation extends StatelessWidget {
  const _Conversation({
    required this.scrollCtrl,
    required this.messages,
    required this.liveUserText,
    required this.liveAiText,
  });

  final ScrollController scrollCtrl;
  final List<Message> messages;
  final String liveUserText;
  final String liveAiText;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (final m in messages) {
      if (m.role != Role.user && m.role != Role.assistant) continue;
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
                    OcColors.surface,
                    OcColors.surface.withValues(alpha: 0),
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
                  ? const Color(0xFF3D6BFF)
                  : OcColors.textSubtitle,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 16,
              height: 1.5,
              color: muted ? OcColors.textSubtitle : OcColors.textBody,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.active,
    required this.onMic,
    required this.onMenu,
    required this.onSettings,
  });

  final bool active;
  final VoidCallback onMic;
  final VoidCallback onMenu;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 8, 40, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: onMenu,
            icon: const Icon(Icons.more_vert,
                size: 28, color: OcColors.textPrimary),
            tooltip: 'Menu',
          ),
          GestureDetector(
            onTap: onMic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: active ? OcColors.danger : OcColors.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.mic, color: Colors.white, size: 30),
            ),
          ),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(Icons.settings,
                size: 28, color: OcColors.textPrimary),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}
