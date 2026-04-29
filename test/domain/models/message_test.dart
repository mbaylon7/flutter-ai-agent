import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/domain/models/message.dart';

void main() {
  test('Message.fromJson parses a simple user message', () {
    final m = Message.fromJson({
      'role': 'user',
      'content': [
        {'type': 'text', 'text': 'Hi'}
      ],
      'timestamp': 1700000000000,
      '__openclaw': {'id': '7e42566e', 'seq': 1},
    });
    expect(m.role, Role.user);
    expect(m.parts.length, 1);
    expect(m.parts.first, isA<TextPart>());
    expect(m.visibleText, 'Hi');
    expect(m.openclawId, '7e42566e');
  });

  test('Message.fromJson parses an assistant message with thinking + toolCall',
      () {
    final m = Message.fromJson({
      'role': 'assistant',
      'content': [
        {'type': 'thinking', 'thinking': 'Let me think...'},
        {'type': 'text', 'text': 'Searching now'},
        {
          'type': 'toolCall',
          'id': 'toolu_X',
          'name': 'web.search',
          'arguments': {'q': 'pizza'},
        },
      ],
      'timestamp': 1700000000000,
    });
    expect(m.role, Role.assistant);
    expect(m.parts.length, 3);
    expect(m.parts[0], isA<ThinkingPart>());
    expect(m.parts[1], isA<TextPart>());
    expect(m.parts[2], isA<ToolCallPart>());
    expect(m.visibleText, 'Searching now');
    expect(m.toolCalls.length, 1);
    expect(m.toolCalls.first.name, 'web.search');
  });

  test('Message.fromJson parses a toolResult message', () {
    final m = Message.fromJson({
      'role': 'toolResult',
      'toolCallId': 'toolu_X',
      'toolName': 'web.search',
      'content': [
        {'type': 'text', 'text': 'Found 3 results'}
      ],
      'isError': false,
      'timestamp': 1700000000000,
    });
    expect(m.role, Role.toolResult);
    expect(m.toolCallId, 'toolu_X');
    expect(m.toolName, 'web.search');
    expect(m.isError, false);
    expect(m.visibleText, 'Found 3 results');
  });

  test('copyWith preserves unspecified', () {
    final m = Message(
      role: Role.assistant,
      parts: const [TextPart('hi')],
      createdAt: DateTime(2026),
      streaming: StreamingState.partial,
    );
    final next =
        m.copyWith(streaming: StreamingState.finalized);
    expect(next.streaming, StreamingState.finalized);
    expect(next.role, Role.assistant);
    expect(next.parts.length, 1);
  });
}
