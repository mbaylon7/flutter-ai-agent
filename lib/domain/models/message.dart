enum Role { user, assistant, system, tool, toolResult }

enum StreamingState { none, partial, finalized, failed }

/// A part inside a message's `content` array.
sealed class ContentPart {
  const ContentPart();
}

class TextPart extends ContentPart {
  const TextPart(this.text);
  final String text;
}

class ThinkingPart extends ContentPart {
  const ThinkingPart(this.thinking);
  final String thinking;
}

class ToolCallPart extends ContentPart {
  const ToolCallPart({
    required this.id,
    required this.name,
    required this.arguments,
  });
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class UnknownPart extends ContentPart {
  const UnknownPart(this.type);
  final String type;
}

ContentPart parseContentPart(Map<String, dynamic> p) {
  switch (p['type']) {
    case 'text':
      return TextPart(p['text'] as String? ?? '');
    case 'thinking':
      return ThinkingPart(p['thinking'] as String? ?? '');
    case 'toolCall':
      return ToolCallPart(
        id: p['id'] as String? ?? '',
        name: p['name'] as String? ?? '',
        arguments: (p['arguments'] as Map?)?.cast<String, dynamic>() ??
            const {},
      );
    default:
      return UnknownPart((p['type'] as String?) ?? 'unknown');
  }
}

class Message {
  const Message({
    required this.role,
    required this.parts,
    required this.createdAt,
    required this.streaming,
    this.toolCallId,
    this.toolName,
    this.isError = false,
    this.openclawId,
    this.runId,
  });

  final Role role;
  final List<ContentPart> parts;
  final DateTime createdAt;
  final StreamingState streaming;

  /// Tool-result-only fields.
  final String? toolCallId;
  final String? toolName;
  final bool isError;

  /// Internal gateway tracking id; useful for dedup. May be null on streamed messages.
  final String? openclawId;

  /// `runId` from chat.send response (used to abort).
  final String? runId;

  /// Convenience: visible plain text aggregated from `text` parts only.
  String get visibleText {
    final buf = StringBuffer();
    for (final p in parts) {
      if (p is TextPart) buf.write(p.text);
    }
    return buf.toString();
  }

  /// Convenience: tool calls (excluding thinking and text).
  List<ToolCallPart> get toolCalls =>
      parts.whereType<ToolCallPart>().toList(growable: false);

  factory Message.fromJson(Map<String, dynamic> j) {
    final role = _parseRole(j['role'] as String?);
    final ts = (j['timestamp'] as num?)?.toInt() ?? 0;
    final ow = (j['__openclaw'] as Map?)?.cast<String, dynamic>();

    if (role == Role.toolResult) {
      // toolResult messages carry their own structure
      final content = (j['content'] as List?) ?? const [];
      return Message(
        role: role,
        parts: content
            .cast<Map>()
            .map((p) => parseContentPart(p.cast<String, dynamic>()))
            .toList(growable: false),
        createdAt: DateTime.fromMillisecondsSinceEpoch(ts),
        streaming: StreamingState.finalized,
        toolCallId: j['toolCallId'] as String?,
        toolName: j['toolName'] as String?,
        isError: (j['isError'] as bool?) ?? false,
        openclawId: ow?['id'] as String?,
      );
    }

    final content = (j['content'] as List?) ?? const [];
    return Message(
      role: role,
      parts: content
          .cast<Map>()
          .map((p) => parseContentPart(p.cast<String, dynamic>()))
          .toList(growable: false),
      createdAt: DateTime.fromMillisecondsSinceEpoch(ts),
      streaming: StreamingState.finalized,
      openclawId: ow?['id'] as String?,
    );
  }

  Message copyWith({
    Role? role,
    List<ContentPart>? parts,
    DateTime? createdAt,
    StreamingState? streaming,
    String? toolCallId,
    String? toolName,
    bool? isError,
    String? openclawId,
    String? runId,
  }) =>
      Message(
        role: role ?? this.role,
        parts: parts ?? this.parts,
        createdAt: createdAt ?? this.createdAt,
        streaming: streaming ?? this.streaming,
        toolCallId: toolCallId ?? this.toolCallId,
        toolName: toolName ?? this.toolName,
        isError: isError ?? this.isError,
        openclawId: openclawId ?? this.openclawId,
        runId: runId ?? this.runId,
      );

  static Role _parseRole(String? r) => switch (r) {
        'user' => Role.user,
        'assistant' => Role.assistant,
        'system' => Role.system,
        'tool' => Role.tool,
        'toolResult' => Role.toolResult,
        _ => Role.assistant,
      };
}
