import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/domain/voice/sentence_chunker.dart';

void main() {
  group('SentenceChunker.drainSentences', () {
    const chunker = SentenceChunker();

    test('emits no chunks before a complete sentence', () {
      final r = chunker.drainSentences('Hello there', 0);
      expect(r.chunks, isEmpty);
      expect(r.cursor, 0);
    });

    test('emits one chunk after a sentence terminator + space', () {
      final r =
          chunker.drainSentences('Hello there, friend. And one ', 0);
      expect(r.chunks, ['Hello there, friend.']);
      expect(r.cursor, 20);
    });

    test('rejects too-short chunks', () {
      // "Hi." is shorter than minChunkChars (12) — wait for more.
      final r = chunker.drainSentences('Hi. Tell me ', 0);
      expect(r.chunks, isEmpty);
      expect(r.cursor, 0);
    });

    test('emits multiple chunks in one pass', () {
      final r = chunker.drainSentences(
        'I will check the weather. Then I will reply. ',
        0,
      );
      expect(r.chunks, [
        'I will check the weather.',
        'Then I will reply.',
      ]);
    });

    test('advances cursor on subsequent calls', () {
      const accumulated = 'I will check the weather. ';
      final first = chunker.drainSentences(accumulated, 0);
      expect(first.chunks.length, 1);
      // Same accumulated string — nothing new.
      final second = chunker.drainSentences(accumulated, first.cursor);
      expect(second.chunks, isEmpty);
      expect(second.cursor, first.cursor);
    });

    test('forceFlush emits remainder without terminator', () {
      final r = chunker.drainSentences(
        'I will check the weather. Now finalising',
        0,
        forceFlush: true,
      );
      expect(r.chunks, [
        'I will check the weather.',
        'Now finalising',
      ]);
      expect(r.cursor, 'I will check the weather. Now finalising'.length);
    });

    test('paragraph break ends a chunk', () {
      final r = chunker.drainSentences(
        'First paragraph here\n\nSecond starts next ',
        0,
      );
      expect(r.chunks, ['First paragraph here']);
    });

    test('force-splits very long unpunctuated runs', () {
      final shortChunker = const SentenceChunker(maxChunkChars: 40);
      final long =
          'one two three four five six seven eight nine ten eleven twelve';
      final r = shortChunker.drainSentences(long, 0);
      expect(r.chunks, isNotEmpty);
      expect(r.chunks.first.length, lessThanOrEqualTo(40));
      expect(r.chunks.first, startsWith('one two'));
    });
  });
}
