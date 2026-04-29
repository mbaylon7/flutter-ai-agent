import 'dart:async';

import 'package:stt_tts/core/logger.dart';
import 'package:stt_tts/data/gateway/shared/envelope_codec.dart';
import 'package:web_socket_channel/io.dart';

export 'envelope_codec.dart';

/// Minimal interface so tests can swap in a fake.
abstract class RawSocketLike {
  Stream<dynamic> get stream;
  void send(String message);
  Future<void> close();
}

class _IOAdapter implements RawSocketLike {
  _IOAdapter(this._channel);
  final IOWebSocketChannel _channel;

  @override
  Stream<dynamic> get stream => _channel.stream;
  @override
  void send(String message) => _channel.sink.add(message);
  @override
  Future<void> close() => _channel.sink.close();
}

class WsConnection {
  WsConnection.test({required RawSocketLike socket, Logger? log})
      : _socket = socket,
        _log = log ?? Logger(tag: 'ws') {
    _wire();
  }

  factory WsConnection.connect(Uri uri, {Logger? log}) {
    final ch = IOWebSocketChannel.connect(uri);
    return WsConnection.test(socket: _IOAdapter(ch), log: log);
  }

  final RawSocketLike _socket;
  final Logger _log;
  final _frames = StreamController<Frame>.broadcast();
  late final StreamSubscription _sub;

  void _wire() {
    _sub = _socket.stream.listen(
      (raw) {
        if (raw is! String) {
          _log.warn('non-string frame ignored');
          return;
        }
        try {
          _frames.add(decodeFrame(raw));
        } catch (e) {
          _log.error('decode error: $e');
        }
      },
      onError: (Object e) => _log.error('socket error: $e'),
      onDone: () => _frames.close(),
    );
  }

  Stream<Frame> get frames => _frames.stream;

  void send(String raw) => _socket.send(raw);

  Future<void> close() async {
    await _sub.cancel();
    await _frames.close();
    await _socket.close();
  }
}

class RpcError implements Exception {
  RpcError(this.code, this.message, {this.details});
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  @override
  String toString() => 'RpcError($code): $message';
}

class RpcChannel {
  RpcChannel(this._conn, {String Function()? idGen})
      : _idGen = idGen ??
            (() => DateTime.now().microsecondsSinceEpoch.toString()) {
    _sub = _conn.frames.listen(_onFrame);
  }

  final WsConnection _conn;
  final String Function() _idGen;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  late final StreamSubscription _sub;

  /// Stream of server-pushed events (no res correlation).
  Stream<EventFrame> get events =>
      _conn.frames.where((f) => f is EventFrame).cast<EventFrame>();

  Future<Map<String, dynamic>> request({
    required String method,
    required Map<String, dynamic> params,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final id = _idGen();
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _conn.send(encodeReq(id: id, method: method, params: params));
    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw RpcError('TIMEOUT', 'request $method timed out');
    });
  }

  void _onFrame(Frame f) {
    if (f is! ResFrame) return;
    final completer = _pending.remove(f.id);
    if (completer == null) return;
    if (f.ok) {
      completer.complete(f.payload ?? const {});
    } else {
      final e = f.error!;
      completer.completeError(
        RpcError(e.code, e.message, details: e.details),
      );
    }
  }

  Future<void> close() async {
    await _sub.cancel();
    for (final c in _pending.values) {
      c.completeError(RpcError('CANCELLED', 'channel closed'));
    }
    _pending.clear();
  }
}
