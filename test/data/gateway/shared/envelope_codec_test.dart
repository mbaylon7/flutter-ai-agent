import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/shared/envelope_codec.dart';

void main() {
  group('decodeFrame', () {
    test('decodes a request', () {
      final f = decodeFrame(
        '{"type":"req","id":"X","method":"connect","params":{"a":1}}',
      );
      expect(f, isA<ReqFrame>());
      final r = f as ReqFrame;
      expect(r.id, 'X');
      expect(r.method, 'connect');
      expect(r.params, {'a': 1});
    });

    test('decodes an ok response (gateway uses "payload" field)', () {
      final f = decodeFrame(
        '{"type":"res","id":"X","ok":true,"payload":{"hello":"world"}}',
      );
      expect(f, isA<ResFrame>());
      final r = f as ResFrame;
      expect(r.ok, true);
      expect(r.payload, {'hello': 'world'});
      expect(r.error, null);
    });

    test('decodes an error response', () {
      final f = decodeFrame(
        '{"type":"res","id":"X","ok":false,"error":{"code":"X","message":"M"}}',
      );
      final r = f as ResFrame;
      expect(r.ok, false);
      expect(r.error?.code, 'X');
      expect(r.error?.message, 'M');
    });

    test('decodes an event with seq', () {
      final f = decodeFrame(
        '{"type":"event","event":"chat.delta","payload":{"t":"hi"},"seq":7}',
      );
      final e = f as EventFrame;
      expect(e.event, 'chat.delta');
      expect(e.payload, {'t': 'hi'});
      expect(e.seq, 7);
    });

    test('decodes captured connect.challenge', () {
      final f = decodeFrame(
        '{"type":"event","event":"connect.challenge","payload":{"nonce":"N","ts":1}}',
      );
      expect(f, isA<EventFrame>());
      expect((f as EventFrame).payload['nonce'], 'N');
    });
  });

  test('encodeReq serializes the request shape', () {
    final s = encodeReq(id: 'X', method: 'connect', params: {'a': 1});
    expect(s, '{"type":"req","id":"X","method":"connect","params":{"a":1}}');
  });
}
