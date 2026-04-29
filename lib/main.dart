import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'STT & TTS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const SttTtsHomePage(),
    );
  }
}

class SttTtsHomePage extends StatefulWidget {
  const SttTtsHomePage({super.key});

  @override
  State<SttTtsHomePage> createState() => _SttTtsHomePageState();
}

class _SttTtsHomePageState extends State<SttTtsHomePage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController(
    text: 'Hello! This is a TTS test.',
  );
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  bool _speechEnabled = false;
  bool _ttsReady = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _userWantsToListen = false; // true while user hasn't tapped stop
  bool _hasReceivedFinalResult = false; // true after we got a final transcription

  String? _speechLocaleId;

  final double _speechRate = 0.56;
  final double _pitch = 1.10;

  List<Map<String, String>> _voices = [];
  String? _selectedVoiceName;

  double _minSoundLevel = 50000;
  double _maxSoundLevel = -50000;
  double _currentSoundLevel = 0;

  DateTime _lastSoundLevelUpdate = DateTime.now();

  // Pulse animation for the mic button
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAll();
    });
  }

  Future<void> _initAll() async {
    await _initTts();
    await _initSpeech();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _speechToText.stop();
    _flutterTts.stop();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speechToText.initialize(
        onStatus: _onSpeechStatus,
        onError: _onSpeechError,
        debugLogging: false,
      );

      String? localeId;

      if (available) {
        final locales = await _speechToText.locales();
        final systemLocale = await _speechToText.systemLocale();

        localeId = systemLocale?.localeId;
        if (localeId == null ||
            !locales.any((locale) => locale.localeId == localeId)) {
          final english = locales
              .where((e) => e.localeId.startsWith('en'))
              .toList();
          if (english.isNotEmpty) {
            localeId = english.first.localeId;
          } else if (locales.isNotEmpty) {
            localeId = locales.first.localeId;
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _speechEnabled = available;
        _speechLocaleId = localeId;
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() => _speechEnabled = false);
    } on PlatformException {
      if (!mounted) return;
      setState(() => _speechEnabled = false);
    }
  }

  Future<void> _initTts() async {
    _flutterTts.setStartHandler(() {
      if (!mounted) return;
      setState(() => _isSpeaking = true);
    });

    _flutterTts.setCompletionHandler(() {
      if (!mounted) return;
      setState(() => _isSpeaking = false);
    });

    _flutterTts.setCancelHandler(() {
      if (!mounted) return;
      setState(() => _isSpeaking = false);
    });

    _flutterTts.setErrorHandler((message) {
      if (!mounted) return;
      setState(() => _isSpeaking = false);
      _showSnackBar('TTS error: $message');
    });

    try {
      await _flutterTts.awaitSpeakCompletion(false);
      try {
        await _flutterTts.setEngine('com.google.android.tts');
      } catch (_) {
        // Not critical if unsupported.
      }

      await _flutterTts.setVolume(1.0);
      await _flutterTts.setSpeechRate(_speechRate);
      await _flutterTts.setPitch(_pitch);

      final chosenLanguage = await _pickPreferredLanguage();
      await _flutterTts.setLanguage(chosenLanguage);

      final voices = await _loadVoicesForLanguage(chosenLanguage);
      final preferredVoice = _pickPreferredVoice(voices, chosenLanguage);

      if (preferredVoice != null) {
        await _flutterTts.setVoice(preferredVoice);
      }

      if (!mounted) return;
      setState(() {
        _voices = voices;
        _selectedVoiceName = preferredVoice != null
            ? _voiceKey(preferredVoice)
            : (voices.isNotEmpty ? _voiceKey(voices.first) : null);
        _ttsReady = true;
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() => _ttsReady = false);
    } on PlatformException {
      if (!mounted) return;
      setState(() => _ttsReady = false);
    }
  }

  Future<String> _pickPreferredLanguage() async {
    try {
      final raw = await _flutterTts.getLanguages;
      final languages = <String>[];
      if (raw is List) {
        for (final item in raw) {
          final value = item.toString();
          if (value.isNotEmpty) {
            languages.add(value);
          }
        }
      }

      const preferred = ['en-US', 'en_US', 'en-GB', 'en_GB'];
      for (final lang in preferred) {
        if (languages.contains(lang)) {
          return lang;
        }
      }

      final english = languages
          .where((l) => l.toLowerCase().startsWith('en'))
          .toList();
      if (english.isNotEmpty) {
        return english.first;
      }
      if (languages.isNotEmpty) {
        return languages.first;
      }
    } catch (_) {
      // fall through
    }

    return 'en-US';
  }

  static const int _maxVoices = 10;

  Future<List<Map<String, String>>> _loadVoicesForLanguage(
      String language) async {
    final allMatching = <Map<String, String>>[];
    final dynamic voicesData = await _flutterTts.getVoices;

    final normalizedLang = language.toLowerCase().replaceAll('_', '-');
    final langPrefix = normalizedLang.split('-').first;

    if (voicesData is List) {
      for (final voice in voicesData) {
        if (voice is Map) {
          final name = voice['name']?.toString();
          final locale = voice['locale']?.toString();
          if (name != null && locale != null) {
            final normalizedLocale =
                locale.toLowerCase().replaceAll('_', '-');
            if (normalizedLocale == normalizedLang ||
                normalizedLocale.startsWith(langPrefix)) {
              allMatching.add({'name': name, 'locale': locale});
            }
          }
        }
      }
    }

    // Sort by quality score (best first)
    allMatching.sort((a, b) => _voiceScore(b).compareTo(_voiceScore(a)));

    // Keep only premium/high-quality voices (score > 0)
    final premium = allMatching.where((v) => _voiceScore(v) > 0).toList();

    // If we have premium voices, use those; otherwise fall back to all matching
    final result = premium.isNotEmpty ? premium : allMatching;

    // Limit to top entries to keep the dropdown manageable
    return result.length > _maxVoices ? result.sublist(0, _maxVoices) : result;
  }

  Map<String, String>? _pickPreferredVoice(
    List<Map<String, String>> voices,
    String language,
  ) {
    if (voices.isEmpty) {
      return null;
    }

    final pool = List<Map<String, String>>.from(voices);
    pool.sort((a, b) => _voiceScore(b).compareTo(_voiceScore(a)));
    return pool.first;
  }

  int _voiceScore(Map<String, String> voice) {
    final name = (voice['name'] ?? '').toLowerCase();
    var score = 0;

    if (name.contains('wavenet') ||
        name.contains('neural') ||
        name.contains('studio') ||
        name.contains('premium') ||
        name.contains('journey')) {
      score += 100;
    }

    if (name.contains('seanet') || name.contains('tpf')) {
      score += 60;
    }

    if (name.contains('female')) {
      score += 15;
    }

    if (name.contains('default')) {
      score -= 25;
    }

    if (name.contains('local') || name.contains('embedded')) {
      score -= 15;
    }

    return score;
  }

  /// Unique key for a voice entry (avoids collisions if two voices share the same name).
  String _voiceKey(Map<String, String> voice) =>
      '${voice['name']}|${voice['locale']}';

  // Helper to find voice by composite key
  Map<String, String>? get _selectedVoice {
    if (_selectedVoiceName == null) return null;
    try {
      return _voices.firstWhere((v) => _voiceKey(v) == _selectedVoiceName);
    } catch (_) {
      return _voices.isNotEmpty ? _voices.first : null;
    }
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;

    final isNowListening = status == SpeechToText.listeningStatus;
    setState(() => _isListening = isNowListening);

    // Engine stopped on its own but user hasn't tapped stop
    if (!isNowListening &&
        status == SpeechToText.doneStatus &&
        _userWantsToListen) {
      // If we already got a final result with text, the user is done talking
      if (_hasReceivedFinalResult) {
        _userWantsToListen = false;
        _hasReceivedFinalResult = false;
        if (mounted) setState(() => _isListening = false);
        return;
      }

      // No result yet — auto-restart (user hasn't spoken yet or brief silence)
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && _userWantsToListen && !_isListening) {
          _startListening();
        }
      });
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;

    final msg = error.errorMsg;

    // Transient "no match" — ignore, auto-restart will handle it
    if (msg.contains('error_no_match')) return;

    // Fatal errors — fully stop
    _userWantsToListen = false;
    setState(() => _isListening = false);

    if (msg.contains('error_network')) {
      _showSnackBar('Network error — speech recognition requires internet.');
    } else if (msg.contains('error_audio')) {
      _showSnackBar('Audio error — check microphone permissions.');
    } else if (msg.contains('error_client')) {
      _showSnackBar('Microphone may not be available.');
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() {
      // Live-fill the text area as speech is recognized
      if (result.recognizedWords.trim().isNotEmpty) {
        final formatted = _smartFormat(result.recognizedWords);
        _textController.text = formatted;
        // Move cursor to end
        _textController.selection = TextSelection.collapsed(
          offset: _textController.text.length,
        );
      }

      // Mark that we got a final transcription — next long pause will end listening
      if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
        _hasReceivedFinalResult = true;
      }
    });
  }

  /// Smart formatting: capitalize sentences, clean up punctuation spacing.
  String _smartFormat(String text) {
    if (text.isEmpty) return text;

    var result = text;

    // Capitalize first character
    result = result[0].toUpperCase() + result.substring(1);

    // Capitalize after sentence-ending punctuation (. ! ?)
    result = result.replaceAllMapped(
      RegExp(r'([.!?])\s+(\w)'),
      (m) => '${m[1]} ${m[2]!.toUpperCase()}',
    );

    // Ensure single space after commas, periods, etc.
    result = result.replaceAllMapped(
      RegExp(r'([,;:])(\w)'),
      (m) => '${m[1]} ${m[2]}',
    );

    // Remove space before punctuation
    result = result.replaceAll(RegExp(r'\s+([,.:;!?])'), r'$1');

    return result;
  }

  void _onSoundLevelChange(double level) {
    if (!mounted) return;

    final now = DateTime.now();
    if (now.difference(_lastSoundLevelUpdate).inMilliseconds < 100) {
      return; // Skip update, too soon
    }
    _lastSoundLevelUpdate = now;

    setState(() {
      _minSoundLevel = min(_minSoundLevel, level);
      _maxSoundLevel = max(_maxSoundLevel, level);
      _currentSoundLevel = level;
    });
  }

  /// 0.0 – 1.0 normalized sound level for the visual ring.
  double get _normalizedSoundLevel {
    final range = (_maxSoundLevel - _minSoundLevel).abs();
    if (!_isListening || range < 1e-6) return 0;
    return ((_currentSoundLevel - _minSoundLevel) / range).clamp(0.0, 1.0);
  }

  Future<void> _toggleListening() async {
    if (!_speechEnabled) {
      _showSnackBar('Speech recognition not available.');
      return;
    }

    if (_userWantsToListen) {
      // User tapped stop — fully stop
      _userWantsToListen = false;
      await _speechToText.stop();
      if (!mounted) return;
      setState(() => _isListening = false);
      return;
    }

    // Stop TTS first to avoid feedback loop
    if (_isSpeaking) {
      await _stopSpeaking();
    }

    setState(() {
      _minSoundLevel = 50000;
      _maxSoundLevel = -50000;
      _currentSoundLevel = 0;
      _hasReceivedFinalResult = false;
      _userWantsToListen = true;
    });

    await _startListening();
  }

  Future<void> _startListening() async {
    try {
      await _speechToText.listen(
        onResult: _onSpeechResult,
        onSoundLevelChange: _onSoundLevelChange,
        localeId: _speechLocaleId,
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 3),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: false,
          autoPunctuation: true,
        ),
      );
    } on PlatformException catch (e) {
      _userWantsToListen = false;
      _showSnackBar('Failed to start listening: ${e.message ?? 'unknown'}');
    }
  }

  Future<void> _speakText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnackBar('Please enter text first.');
      return;
    }

    if (!_ttsReady) {
      _showSnackBar('TTS is not ready yet.');
      return;
    }

    // Stop STT first to avoid feedback loop (speaker audio picked up by mic)
    if (_isListening || _userWantsToListen) {
      _userWantsToListen = false;
      await _speechToText.stop();
      if (mounted) setState(() => _isListening = false);
    }

    try {
      await _flutterTts.stop();
      // Small delay to let cancel callbacks flush before starting new speech
      await Future.delayed(const Duration(milliseconds: 50));
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setSpeechRate(_speechRate);
      await _flutterTts.setPitch(_pitch);

      final voice = _selectedVoice;
      if (voice != null) {
        await _flutterTts.setVoice(voice);
      }

      final result = await _flutterTts.speak(text);
      if (result is int && result != 1) {
        _showSnackBar('TTS failed to start. Code: $result');
      }
    } on PlatformException catch (e) {
      _showSnackBar('TTS failed: ${e.message ?? 'unknown error'}');
    }
  }

  Future<void> _stopSpeaking() async {
    await _flutterTts.stop();
    if (!mounted) return;
    setState(() => _isSpeaking = false);
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Whether the mic/wave animation should be active (listening OR speaking).
  bool get _animationActive => _userWantsToListen || _isSpeaking;

  // ── Sound wave bar heights (simulated from sound level or TTS pulse) ──
  List<double> get _waveBars {
    if (!_animationActive) {
      return List.generate(24, (_) => 0.08);
    }

    if (_isSpeaking) {
      // Simulate wave from pulse animation while TTS is playing
      final pulse = _pulseAnimation.value;
      final rng = Random(DateTime.now().millisecond ~/ 100);
      return List.generate(24, (i) {
        final base = 0.3 + (pulse - 1.0) * 2.5;
        final wave = base + (rng.nextDouble() * 0.35);
        return wave.clamp(0.08, 1.0);
      });
    }

    // STT mode — react to sound level
    final rng = Random(_currentSoundLevel.toInt());
    final base = _normalizedSoundLevel;
    return List.generate(24, (i) {
      final wave = (base * 0.6) + (rng.nextDouble() * base * 0.4);
      return wave.clamp(0.08, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = _userWantsToListen;
    final animActive = _animationActive;
    const coral = Color(0xFFE8614D);
    const coralTTS = Color(0xFF4A90D9); // Blue accent when TTS is playing

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE8614D),
              Color(0xFFF4A68F),
              Color(0xFFFCDDD4),
              Color(0xFFF9F0EE),
            ],
            stops: [0.0, 0.3, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Top bar ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.headset_rounded,
                        color: Colors.white.withValues(alpha: 0.85), size: 26),
                    const Spacer(),
                    if (_isSpeaking)
                      IconButton(
                        onPressed: _stopSpeaking,
                        icon: const Icon(Icons.stop_rounded,
                            color: Colors.white, size: 26),
                      ),
                  ],
                ),
              ),

              // ── Centered mic area (takes most of the screen) ──
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Mic button with pulse ring
                      SizedBox(
                        width: 170,
                        height: 170,
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            final accentColor = _isSpeaking ? coralTTS : coral;
                            final pulseLevel = _isSpeaking
                                ? (_pulseAnimation.value - 1.0) * 3.0
                                : _normalizedSoundLevel;
                            final ringScale = animActive
                                ? 1.0 +
                                    (pulseLevel * 0.3) +
                                    ((_pulseAnimation.value - 1.0) * 0.5)
                                : 1.0;

                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                // Outer ring
                                Transform.scale(
                                  scale: animActive ? ringScale : 1.0,
                                  child: Container(
                                    width: 150,
                                    height: 150,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: animActive
                                            ? Colors.white.withValues(
                                                alpha: 0.4 +
                                                    (pulseLevel.clamp(0.0, 1.0) * 0.4))
                                            : Colors.white.withValues(alpha: 0.35),
                                        width: animActive ? 4 : 2.5,
                                      ),
                                    ),
                                  ),
                                ),
                                // Inner mic/speaker circle
                                Container(
                                  width: 105,
                                  height: 105,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: accentColor.withValues(
                                            alpha: animActive ? 0.3 : 0.12),
                                        blurRadius: animActive
                                            ? 24 + (pulseLevel.clamp(0.0, 1.0) * 12)
                                            : 12,
                                        spreadRadius: animActive
                                            ? pulseLevel.clamp(0.0, 1.0) * 4
                                            : 0,
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    onPressed: _isSpeaking
                                        ? _stopSpeaking
                                        : _toggleListening,
                                    iconSize: 42,
                                    icon: Icon(
                                      _isSpeaking
                                          ? Icons.volume_up_rounded
                                          : active
                                              ? Icons.mic
                                              : Icons.mic_none_rounded,
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Status text
                      Text(
                        _isSpeaking
                            ? 'Speaking...'
                            : active
                                ? 'Listening...'
                                : 'Ready to listen',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          color: animActive
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.9),
                        ),
                      ),

                      if (active && !_isSpeaking) ...[
                        const SizedBox(height: 6),
                        Text(
                          _normalizedSoundLevel > 0.05
                              ? '🔊 Voice detected — ${(_normalizedSoundLevel * 100).toStringAsFixed(0)}%'
                              : '🔇 Waiting for voice...',
                          style: TextStyle(
                            fontSize: 12,
                            color: _normalizedSoundLevel > 0.05
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ],

                      if (_isSpeaking) ...[
                        const SizedBox(height: 6),
                        Text(
                          '🔊 Tap to stop',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],

                      const SizedBox(height: 28),

                      // ── Sound wave bars ──
                      SizedBox(
                        height: 40,
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            final bars = _waveBars;
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(bars.length, (i) {
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  width: 4,
                                  height: 6 + (bars[i] * 34),
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                    color: animActive
                                        ? Colors.white.withValues(
                                            alpha: 0.3 + (bars[i] * 0.7))
                                        : Colors.white.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                );
                              }),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  ),
                ),
              ),

              // ── Compact bottom: text field + cancel in one row ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Text field
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: 46,
                            maxHeight: 100,
                          ),
                          child: TextField(
                            controller: _textController,
                            maxLines: null,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade800,
                            ),
                            decoration: InputDecoration(
                              hintText: active
                                  ? 'Transcribing...'
                                  : 'Type or speak...',
                              hintStyle: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 14,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                      // Speak button
                      IconButton(
                        onPressed: _isSpeaking ? _stopSpeaking : _speakText,
                        icon: Icon(
                          _isSpeaking
                              ? Icons.stop_rounded
                              : Icons.volume_up_rounded,
                          color: coral,
                          size: 22,
                        ),
                      ),
                      // Clear/Cancel button
                      IconButton(
                        onPressed: active
                            ? _toggleListening
                            : () => _textController.clear(),
                        icon: Icon(
                          active ? Icons.close_rounded : Icons.delete_outline,
                          color: Colors.grey.shade500,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
