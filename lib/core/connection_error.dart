import 'dart:async';
import 'dart:io';

/// Map a raw exception thrown during gateway pairing/connection to a
/// short message safe to display to a user. The original error is
/// expected to be logged separately for debugging.
String friendlyConnectionError(Object error) {
  if (error is TimeoutException) return 'Connection timeout';
  if (error is SocketException) {
    final msg = error.osError?.message ?? error.message;
    if (msg.toLowerCase().contains('host')) return 'Network connection failed';
    return 'Network connection failed';
  }
  if (error is HandshakeException) return 'Secure connection failed';
  if (error is HttpException) return 'Network connection failed';
  if (error is FormatException) return 'Invalid connection details';

  final text = error.toString().toLowerCase();
  if (text.contains('signature') || text.contains('unauthor')) {
    return 'Invalid connection details';
  }
  if (text.contains('timeout')) return 'Connection timeout';
  if (text.contains('socket') || text.contains('network')) {
    return 'Network connection failed';
  }
  return 'Unable to connect to agent';
}
