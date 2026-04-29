import 'dart:convert';

sealed class Frame {
  const Frame();
}

class ReqFrame extends Frame {
  const ReqFrame({
    required this.id,
    required this.method,
    required this.params,
  });
  final String id;
  final String method;
  final Map<String, dynamic> params;
}

class ResFrame extends Frame {
  const ResFrame({
    required this.id,
    required this.ok,
    this.payload,
    this.error,
  });
  final String id;
  final bool ok;

  /// Gateway uses "payload" (not "result") for success responses.
  final Map<String, dynamic>? payload;
  final ResError? error;
}

class ResError {
  const ResError({
    required this.code,
    required this.message,
    this.details,
  });
  final String code;
  final String message;
  final Map<String, dynamic>? details;
}

class EventFrame extends Frame {
  const EventFrame({
    required this.event,
    required this.payload,
    this.seq,
  });
  final String event;
  final Map<String, dynamic> payload;
  final int? seq;
}

Frame decodeFrame(String raw) {
  final m = jsonDecode(raw) as Map<String, dynamic>;
  switch (m['type']) {
    case 'req':
      return ReqFrame(
        id: m['id'] as String,
        method: m['method'] as String,
        params: (m['params'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
    case 'res':
      final ok = m['ok'] as bool;
      return ResFrame(
        id: m['id'] as String,
        ok: ok,
        payload:
            ok ? (m['payload'] as Map?)?.cast<String, dynamic>() : null,
        error: !ok && m['error'] != null
            ? ResError(
                code: ((m['error'] as Map)['code'] ?? '') as String,
                message: ((m['error'] as Map)['message'] ?? '') as String,
                details: ((m['error'] as Map)['details'] as Map?)
                    ?.cast<String, dynamic>(),
              )
            : null,
      );
    case 'event':
      return EventFrame(
        event: m['event'] as String,
        payload: (m['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        seq: m['seq'] as int?,
      );
    default:
      throw FormatException('unknown frame type: ${m['type']}');
  }
}

String encodeReq({
  required String id,
  required String method,
  required Map<String, dynamic> params,
}) =>
    jsonEncode(
      {'type': 'req', 'id': id, 'method': method, 'params': params},
    );
