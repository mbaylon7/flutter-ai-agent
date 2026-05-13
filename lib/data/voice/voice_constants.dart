import 'package:speech_to_text/speech_to_text.dart';

class VoiceConstants {
  // Natural-cadence values. Android's flutter_tts treats ~0.5 as a real-time
  // speaking pace, and pitch 1.0 avoids the chipmunk lift that made earlier
  // voices feel robotic.
  static const double speechRate = 0.50;
  static const double pitch = 1.0;
  static const Duration pauseFor = Duration(seconds: 3);
  static const Duration listenFor = Duration(minutes: 2);
  static const ListenMode listenMode = ListenMode.dictation;
  static const bool autoPunctuation = true;

  static const int maxVoices = 10;

  // Sentinel sound-level seeds that are inverted intentionally — see CLAUDE.md.
  static const double soundLevelSeedMin = 50000;
  static const double soundLevelSeedMax = -50000;
}
