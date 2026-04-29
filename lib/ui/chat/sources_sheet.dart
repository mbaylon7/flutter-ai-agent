import 'package:flutter/material.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/domain/markdown/tool_label.dart';
import 'package:stt_tts/domain/models/message.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bottom-sheet body listing the tool calls that back an assistant reply.
///
/// [calls] — the ToolCallParts from the assistant message.
/// [resultsByCallId] — map from call.id → toolResult Message (may be incomplete
///   if still streaming).
class SourcesSheet extends StatelessWidget {
  const SourcesSheet({
    super.key,
    required this.calls,
    required this.resultsByCallId,
  });

  final List<ToolCallPart> calls;
  final Map<String, Message> resultsByCallId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: OcColors.borderTint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Sources',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(height: 16),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: calls.length,
              itemBuilder: (context, i) {
                return _SourceRow(
                  call: calls[i],
                  result: resultsByCallId[calls[i].id],
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single source row
// ---------------------------------------------------------------------------

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.call, this.result});

  final ToolCallPart call;
  final Message? result;

  /// Extracts the first https?:// URL from the result text, or null.
  static String? _extractUrl(String text) {
    final match = RegExp(r'https?://\S+').firstMatch(text);
    return match?.group(0);
  }

  static Icon _iconForTool(String name) {
    final lower = name.toLowerCase();
    if (lower.startsWith('web') ||
        lower.startsWith('fetch') ||
        lower == 'read_url' ||
        lower == 'searchWeb'.toLowerCase()) {
      return const Icon(Icons.language, size: 18);
    }
    if (lower.contains('file') || lower == 'read_file') {
      return const Icon(Icons.description_outlined, size: 18);
    }
    if (lower == 'bash' ||
        lower == 'shell' ||
        lower == 'runcommand' ||
        lower == 'python' ||
        lower == 'runpython') {
      return const Icon(Icons.settings_outlined, size: 18);
    }
    return const Icon(Icons.attach_file, size: 18);
  }

  @override
  Widget build(BuildContext context) {
    final result = this.result;

    // Build snippet text from result parts
    String snippet;
    String? url;
    bool failed = false;

    if (result == null) {
      snippet = '(no result)';
    } else if (result.isError) {
      snippet = '(failed)';
      failed = true;
    } else {
      final buf = StringBuffer();
      for (final p in result.parts) {
        if (p is TextPart) buf.write(p.text);
      }
      final full = buf.toString().trim();
      snippet = full.length > 80 ? '${full.substring(0, 80)}…' : full;
      if (snippet.isEmpty) snippet = '(no result)';
      url = _extractUrl(full);
    }

    final tile = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _iconForTool(call.name),
      title: Text(
        labelForTool(call.name),
        style: const TextStyle(fontSize: 13, color: OcColors.textBody),
      ),
      subtitle: Text(
        snippet,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: failed ? OcColors.danger : OcColors.textMeta,
        ),
      ),
      trailing: url != null
          ? const Icon(Icons.chevron_right, color: OcColors.textMeta, size: 18)
          : null,
      onTap: url != null
          ? () => launchUrl(Uri.parse(url!),
              mode: LaunchMode.externalApplication)
          : null,
    );

    if (failed) {
      return Opacity(opacity: 0.6, child: tile);
    }
    return tile;
  }
}
