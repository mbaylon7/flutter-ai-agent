import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/core/result.dart';

void main() {
  group('Result', () {
    test('Ok holds value', () {
      const r = Result<int, String>.ok(42);
      expect(r.isOk, true);
      expect(r.isErr, false);
      expect((r as Ok<int, String>).value, 42);
    });

    test('Err holds error', () {
      const r = Result<int, String>.err('boom');
      expect(r.isOk, false);
      expect(r.isErr, true);
      expect((r as Err<int, String>).error, 'boom');
    });

    test('map transforms Ok value', () {
      const r = Result<int, String>.ok(2);
      final mapped = r.map((v) => v * 10);
      expect((mapped as Ok<int, String>).value, 20);
    });

    test('map preserves Err', () {
      const r = Result<int, String>.err('x');
      final mapped = r.map((v) => v * 10);
      expect((mapped as Err<int, String>).error, 'x');
    });

    test('whenOr provides fallback', () {
      const ok = Result<int, String>.ok(5);
      const err = Result<int, String>.err('e');
      expect(ok.whenOr(ok: (v) => v + 1, fallback: -1), 6);
      expect(err.whenOr(ok: (v) => v + 1, fallback: -1), -1);
    });
  });
}
