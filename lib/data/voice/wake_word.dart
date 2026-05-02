import 'dart:async';

import 'package:porcupine_flutter/porcupine_manager.dart';

/// Picovoice Porcupine wrapper for the "Hi/Hey OpenClaw" wake word.
///
/// Lifecycle:
/// - Construct with the AccessKey (from `--dart-define=PICOVOICE_KEY=...`).
/// - `start()` initializes the manager from the bundled `.ppn` keyword files
///   and begins listening. Returns `true` if listening, `false` if anything
///   failed (missing key, missing files, no mic permission, etc.).
/// - The `triggers` stream emits `void` each time a keyword is detected.
///   A 2-second cooldown prevents back-to-back triggers from a single phrase.
/// - `stop()` halts the manager. `dispose()` releases native resources.
///
/// `triggers` is always non-null (created in the field initializer), so
/// callers can subscribe before `start()` and never see a null-deref.
class WakeWordService {
  WakeWordService({required this.accessKey});

  /// Picovoice Console AccessKey. Pass via `--dart-define=PICOVOICE_KEY=...`.
  final String accessKey;

  PorcupineManager? _mgr;
  final _ctl = StreamController<void>.broadcast();
  DateTime _lastTrigger = DateTime.fromMillisecondsSinceEpoch(0);

  /// Stream of trigger events. Always-available; emits nothing until `start()`
  /// succeeds and the user says the keyword.
  Stream<void> get triggers => _ctl.stream;

  /// Returns `true` if the manager started listening, `false` on any failure.
  Future<bool> start() async {
    if (_mgr != null) return true;
    if (accessKey.isEmpty) return false;
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
      _mgr = null;
      return false;
    }
  }

  void _onDetect(int keywordIndex) {
    final now = DateTime.now();
    if (now.difference(_lastTrigger).inSeconds < 2) return; // cooldown
    _lastTrigger = now;
    _ctl.add(null);
  }

  Future<void> stop() async {
    final m = _mgr;
    if (m == null) return;
    _mgr = null;
    try {
      await m.stop();
      await m.delete();
    } catch (_) {/* swallow shutdown errors */}
  }

  Future<void> dispose() async {
    await stop();
    await _ctl.close();
  }
}
