import 'package:speech_to_text/speech_to_text.dart';

class VoiceConstants {
  // FROM CLAUDE.md — tuned values that carry forward verbatim.
  // Do NOT change without referencing CLAUDE.md § "Configuration constants".
  static const double speechRate = 0.56;
  static const double pitch = 1.10;
  static const Duration pauseFor = Duration(seconds: 3);
  static const Duration listenFor = Duration(minutes: 2);
  static const ListenMode listenMode = ListenMode.dictation;
  static const bool autoPunctuation = true;

  static const int maxVoices = 10;

  // Sentinel sound-level seeds that are inverted intentionally — see CLAUDE.md.
  static const double soundLevelSeedMin = 50000;
  static const double soundLevelSeedMax = -50000;
}
