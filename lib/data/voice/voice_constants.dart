/// Voice pipeline tuning constants for the Sherpa-ONNX backend.
class VoiceConstants {
  // TTS speed and pitch are baked into the Piper model; we don't expose
  // them as runtime constants. Speed can be adjusted via
  // OfflineTtsGenerationConfig if needed.

  // Sherpa-ONNX endpoint detection is configured in [SttService] directly,
  // so the old pauseFor / listenFor / ListenMode constants are gone.

  static const int maxVoices = 10;
}
