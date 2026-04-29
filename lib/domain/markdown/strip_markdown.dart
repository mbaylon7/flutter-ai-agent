/// Removes markdown syntax for TTS playback.
///
/// Applies substitutions in order (most specific first):
///   1. Fenced code blocks  → "(code block)"
///   2. Inline code         → raw code text
///   3. **bold** / __bold__ → bold text
///   4. *italic* / _italic_ → italic text
///   5. ~~strike~~          → strike text
///   6. [link text](url)    → link text
///   7. Headings at SOL     → strip leading `#` markers
///   8. List bullets at SOL → strip leading bullet/number markers
///   9. HTML tags           → stripped
///  10. Multiple blank lines → collapsed to two newlines
///
/// This is intentionally simple regex substitution — TTS is forgiving of
/// imperfect output. The ordering ensures **bold** is handled before
/// *italic* to avoid partial matches.
String stripMarkdown(String input) {
  if (input.isEmpty) return '';

  var s = input;

  // 1. Fenced code blocks (``` ... ```) — entire block → "(code block)"
  //    [\s\S]*? matches content lazily across newlines.
  s = s.replaceAllMapped(
    RegExp(r'```[^\n]*\n[\s\S]*?```', multiLine: true),
    (_) => '(code block)',
  );

  // 2. Inline code — `code` → code text
  s = s.replaceAllMapped(
    RegExp(r'`([^`\n]+)`'),
    (m) => m.group(1)!,
  );

  // 3. Bold — **text** or __text__ → text
  s = s.replaceAllMapped(
    RegExp(r'\*\*(.+?)\*\*|__(.+?)__'),
    (m) => m.group(1) ?? m.group(2)!,
  );

  // 4. Italic — *text* or _text_ → text
  s = s.replaceAllMapped(
    RegExp(r'\*(.+?)\*|_(.+?)_'),
    (m) => m.group(1) ?? m.group(2)!,
  );

  // 5. Strikethrough — ~~text~~ → text
  s = s.replaceAllMapped(
    RegExp(r'~~(.+?)~~'),
    (m) => m.group(1)!,
  );

  // 6. Links — [text](url) → text
  s = s.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (m) => m.group(1)!,
  );

  // 7. Headings at line start — strip `###... ` prefix
  s = s.replaceAllMapped(
    RegExp(r'^#{1,6}\s+', multiLine: true),
    (_) => '',
  );

  // 8. List bullets at line start — `- `, `* `, `+ `, `1. `, `12. ` etc.
  s = s.replaceAllMapped(
    RegExp(r'^\s*[-*+]\s+|^\s*\d+\.\s+', multiLine: true),
    (_) => '',
  );

  // 9. HTML tags — strip entirely
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');

  // 10. Normalise runs of 3+ blank lines to two newlines.
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  return s;
}
