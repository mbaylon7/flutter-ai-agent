import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/gateway/shared/ws_connection.dart';

class FakeSocket implements RawSocketLike {
  final _in = StreamController<dynamic>.broadcast();
  final outgoing = <String>[];
  bool closed = false;

  @override
  Stream<dynamic> get stream => _in.stream;
  @override
  void send(String s) => outgoing.add(s);
  @override
  Future<void> close() async {
    closed = true;
  }

  void push(String s) => _in.add(s);
}

void main() {
  test('WsConnection forwards inbound frames as parsed Frames', () async {
    final fake = FakeSocket();
    final conn = WsConnection.test(socket: fake);
    final received = <Frame>[];
    final sub = conn.frames.listen(received.add);

    fake.push(
      '{"type":"event","event":"connect.challenge","payload":{"nonce":"N","ts":1}}',
    );
    await Future.delayed(Duration.zero);

    expect(received.length, 1);
    expect(received.first, isA<EventFrame>());

    await sub.cancel();
    await conn.close();
    expect(fake.closed, true);
  });

  test('send writes encoded request to socket', () {
    final fake = FakeSocket();
    final conn = WsConnection.test(socket: fake);
    conn.send('{"type":"req","id":"X","method":"m","params":{}}');
    expect(
      fake.outgoing,
      ['{"type":"req","id":"X","method":"m","params":{}}'],
    );
  });

  test('RpcChannel resolves matching res frames', () async {
    final fake = FakeSocket();
    final conn = WsConnection.test(socket: fake);
    final rpc = RpcChannel(conn, idGen: () => 'ID-1');

    final future = rpc.request(method: 'health', params: {});
    expect(fake.outgoing.single, contains('"id":"ID-1"'));
    fake.push(
      '{"type":"res","id":"ID-1","ok":true,"payload":{"ok":true}}',
    );

    final result = await future;
    expect(result, {'ok': true});
  });

  test('RpcChannel rejects on error response', () async {
    final fake = FakeSocket();
    final conn = WsConnection.test(socket: fake);
    final rpc = RpcChannel(conn, idGen: () => 'ID-2');
    final future = rpc.request(method: 'x', params: {});
    fake.push(
      '{"type":"res","id":"ID-2","ok":false,"error":{"code":"E","message":"M"}}',
    );
    await expectLater(future, throwsA(isA<RpcError>()));
  });
}
