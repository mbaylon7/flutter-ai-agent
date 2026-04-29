import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/shared/reconnect_loop.dart';

void main() {
  test('backoff sequence is 1,2,4,8,16,30,30,...', () {
    final r = ReconnectLoop();
    expect(r.nextBackoffMs(), 1000);
    expect(r.nextBackoffMs(), 2000);
    expect(r.nextBackoffMs(), 4000);
    expect(r.nextBackoffMs(), 8000);
    expect(r.nextBackoffMs(), 16000);
    expect(r.nextBackoffMs(), 30000);
    expect(r.nextBackoffMs(), 30000);
  });

  test('reset goes back to 800ms (matches gateway default)', () {
    final r = ReconnectLoop();
    r.nextBackoffMs();
    r.nextBackoffMs();
    r.reset();
    expect(r.nextBackoffMs(), 800);
  });
}
