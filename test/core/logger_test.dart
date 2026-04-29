import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/logger.dart';

void main() {
  test('Logger filters below threshold', () {
    final lines = <String>[];
    final log = Logger(tag: 'T', minLevel: LogLevel.warn, sink: lines.add);
    log.debug('debug');
    log.info('info');
    log.warn('warn');
    log.error('error');
    expect(lines.length, 2);
    expect(lines[0], contains('[T] WARN warn'));
    expect(lines[1], contains('[T] ERROR error'));
  });
}
