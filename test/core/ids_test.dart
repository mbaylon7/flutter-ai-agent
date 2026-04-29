import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/ids.dart';

void main() {
  test('newRequestId returns unique v4 UUIDs', () {
    final a = newRequestId();
    final b = newRequestId();
    expect(a, isNot(b));
    expect(a.length, 36);
    expect(
      a,
      matches(RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      )),
    );
  });
}
