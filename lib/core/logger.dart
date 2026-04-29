enum LogLevel { debug, info, warn, error }

class Logger {
  Logger({
    required this.tag,
    this.minLevel = LogLevel.info,
    void Function(String)? sink,
  }) : _sink = sink ?? _defaultSink;

  final String tag;
  final LogLevel minLevel;
  final void Function(String) _sink;

  static void _defaultSink(String line) {
    // ignore: avoid_print
    print(line);
  }

  void debug(String msg) => _emit(LogLevel.debug, msg);
  void info(String msg) => _emit(LogLevel.info, msg);
  void warn(String msg) => _emit(LogLevel.warn, msg);
  void error(String msg) => _emit(LogLevel.error, msg);

  void _emit(LogLevel level, String msg) {
    if (level.index < minLevel.index) return;
    _sink('[$tag] ${level.name.toUpperCase()} $msg');
  }
}
