/// Splits a growing assistant reply into speakable sentence chunks.
///
/// The chunker is stateless. Callers maintain a cursor (number of characters
/// already consumed) and call [drainSentences] each time the streaming text
/// grows. Each call returns the next batch of complete sentences plus the
/// updated cursor.
///
/// Terminators: `.`, `!`, `?`, double newlines. A sentence is only emitted
/// when followed by whitespace or end-of-input AND the chunk has at least
/// [minChunkChars] characters (avoids speaking single-token bursts like
/// `"Hi."`).
///
/// When [forceFlush] is true (assistant message finalized) the remainder
/// past the cursor is emitted as one chunk even if it has no terminator.
class SentenceChunker {
  const SentenceChunker({
    this.minChunkChars = 5,
    this.maxChunkChars = 220,
  });

  final int minChunkChars;

  /// Pathological-case safety: if more than [maxChunkChars] characters have
  /// accumulated without a terminator, force-split at the last whitespace
  /// before this many characters so we don't sit silent on an unpunctuated
  /// monologue.
  final int maxChunkChars;

  ChunkerResult drainSentences(
    String accumulated,
    int cursor, {
    bool forceFlush = false,
  }) {
    if (cursor < 0) cursor = 0;
    if (cursor > accumulated.length) cursor = accumulated.length;
    final chunks = <String>[];
    var i = cursor;
    var sentenceStart = cursor;

    while (i < accumulated.length) {
      final ch = accumulated[i];
      // Commas count as a split point so the TTS drain can insert a short
      // breath pause between clauses. Trailing punctuation is preserved on
      // each chunk so TTS can pick the pause length per chunk.
      final isTerminator =
          ch == '.' || ch == '!' || ch == '?' || ch == ',';
      final isParaBreak = ch == '\n' &&
          i + 1 < accumulated.length &&
          accumulated[i + 1] == '\n';
      if (isTerminator || isParaBreak) {
        final endOfSentence = isParaBreak ? i + 2 : i + 1;
        final atEnd = endOfSentence >= accumulated.length;
        final nextIsWhitespace = !atEnd &&
            _isWhitespace(accumulated.codeUnitAt(endOfSentence));
        if (atEnd || nextIsWhitespace || isParaBreak) {
          final raw = accumulated.substring(sentenceStart, endOfSentence);
          final trimmed = raw.trim();
          if (trimmed.length >= minChunkChars) {
            chunks.add(trimmed);
            sentenceStart = endOfSentence;
            i = endOfSentence;
            continue;
          }
        }
      }

      // Force-split for unpunctuated runs longer than maxChunkChars.
      if (i - sentenceStart >= maxChunkChars) {
        final slice = accumulated.substring(sentenceStart, i);
        final lastSpace = slice.lastIndexOf(' ');
        final breakAt =
            lastSpace > minChunkChars ? sentenceStart + lastSpace : i;
        final chunk = accumulated.substring(sentenceStart, breakAt).trim();
        if (chunk.isNotEmpty) chunks.add(chunk);
        sentenceStart = breakAt;
      }

      i++;
    }

    if (forceFlush && sentenceStart < accumulated.length) {
      final tail = accumulated.substring(sentenceStart).trim();
      if (tail.isNotEmpty) chunks.add(tail);
      sentenceStart = accumulated.length;
    }

    return ChunkerResult(chunks: chunks, cursor: sentenceStart);
  }

  static bool _isWhitespace(int rune) =>
      rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D;
}

class ChunkerResult {
  const ChunkerResult({required this.chunks, required this.cursor});

  /// Newly-completed sentence chunks ready to enqueue for speech.
  final List<String> chunks;

  /// Updated cursor — pass back into the next [SentenceChunker.drainSentences] call.
  final int cursor;
}
