import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:stt_tts/core/theme.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------------------------------------------------------------------------
// Streaming-fence handling
// ---------------------------------------------------------------------------
//
// Strategy: if the markdown text ends with an unclosed fenced code block
// (odd number of ``` markers), artificially close the last open fence before
// handing the string to MarkdownBody. This prevents the parser from emitting
// raw backtick noise. The artificially-closed block may show partial code, but
// it renders cleanly as a code block rather than garbled text. Once the closing
// fence arrives in the next streaming chunk the artificial close is removed and
// the complete block renders normally.
String _trimIncompleteFence(String input) {
  final count = RegExp(r'```').allMatches(input).length;
  if (count % 2 == 0) return input;

  final lastFenceIdx = input.lastIndexOf('```');
  final beforeFence = input.substring(0, lastFenceIdx);
  final afterFence = input.substring(lastFenceIdx + 3);
  // Artificially close the fence so the parser sees a complete block.
  return '$beforeFence\n```\n$afterFence\n```';
}

// ---------------------------------------------------------------------------
// Code-block element builder (HighlightView + copy button)
// ---------------------------------------------------------------------------

/// Custom builder for `pre` (fenced code) elements.
///
/// **Why the text-capture dance?**
/// flutter_markdown routes `visitText` calls through the builder when
/// `_blocks.last.tag` matches the builder key (`'pre'`). If `visitText`
/// returns `null` (the default), no inline child is created for the nested
/// `code` element. That leaves `_inlines` non-empty at the end of parsing and
/// triggers an internal `assert(_inlines.isEmpty)`. To avoid this, we capture
/// the code text ourselves in `visitText`, return a zero-size placeholder so
/// the inline-child chain completes, then emit the real `HighlightView` from
/// `visitElementAfterWithContext` using the captured text.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  final StringBuffer _buffer = StringBuffer();

  @override
  void visitElementBefore(md.Element element) {
    // Reset buffer at the start of each new pre/code element so multiple code
    // blocks on the same page don't bleed into each other.
    _buffer.clear();
  }

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    // Accumulate code text and return an invisible placeholder so the internal
    // _inlines chain gets a non-null child and clears correctly.
    _buffer.write(text.text);
    return const SizedBox.shrink();
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // Use the text we captured in visitText rather than element.textContent,
    // which may be empty when the builder intercepted the text node.
    final code = _buffer.toString().trimRight();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1e2e),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: OcColors.borderTint),
      ),
      child: Stack(
        children: [
          // Scrollable highlight view.
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 12, 40, 12),
              child: HighlightView(
                code,
                language: 'plaintext',
                theme: atomOneDarkTheme,
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ),

          // Copy button pinned to top-right — uses trimmed code.
          Positioned(
            top: 4,
            right: 4,
            child: _CopyButton(code: code),
          ),
        ],
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.code});
  final String code;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('copy_code_button'),
      onPressed: _copy,
      icon: Icon(
        _copied ? Icons.check : Icons.copy_outlined,
        size: 14,
        color: _copied ? OcColors.live : OcColors.textMeta,
      ),
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
      tooltip: _copied ? 'Copied!' : 'Copy code',
    );
  }
}

// ---------------------------------------------------------------------------
// OcMarkdown
// ---------------------------------------------------------------------------

/// Renders assistant message content as styled markdown.
///
/// Uses [MarkdownBody] (not [Markdown]) so it does NOT introduce its own
/// scroll view — the parent chat list owns scrolling.
///
/// Streaming: if [text] ends with an unclosed fenced block the renderer
/// artificially closes it so the parser always sees balanced fences.
class OcMarkdown extends StatelessWidget {
  const OcMarkdown(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final safeText = _trimIncompleteFence(text);

    return MarkdownBody(
      data: safeText,
      selectable: true,
      styleSheet: _buildStyleSheet(),
      builders: {
        'pre': _CodeBlockBuilder(),
      },
      onTapLink: (_, href, title) {
        if (href != null) {
          final uri = Uri.tryParse(href);
          if (uri != null) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      },
    );
  }

  static MarkdownStyleSheet _buildStyleSheet() {
    const monoStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      color: OcColors.accent,
      backgroundColor: OcColors.surface,
    );

    return MarkdownStyleSheet(
      // Paragraphs
      p: const TextStyle(
        color: OcColors.textBody,
        fontSize: 14,
        height: 1.4,
      ),

      // Headings
      h1: const TextStyle(
        color: OcColors.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.bold,
        height: 1.3,
      ),
      h2: const TextStyle(
        color: OcColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        height: 1.3,
      ),
      h3: const TextStyle(
        color: OcColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.bold,
        height: 1.3,
      ),

      // Strong / em
      strong: const TextStyle(
        color: OcColors.textPrimary,
        fontWeight: FontWeight.bold,
      ),
      em: const TextStyle(fontStyle: FontStyle.italic),

      // Inline code
      code: monoStyle,

      // Blockquote
      blockquote: const TextStyle(
        color: OcColors.textSubtitle,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: OcColors.borderTint,
            width: 3,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),

      // Links
      a: const TextStyle(
        color: OcColors.accent,
        decoration: TextDecoration.underline,
        decorationColor: OcColors.accent,
      ),

      // List bullets
      listBullet: const TextStyle(
        color: OcColors.accent,
        fontSize: 14,
      ),
    );
  }
}
