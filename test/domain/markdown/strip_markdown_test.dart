import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/domain/markdown/strip_markdown.dart';

void main() {
  group('stripMarkdown', () {
    test('1. removes **bold**', () {
      expect(stripMarkdown('**bold**'), 'bold');
    });

    test('2. removes *italic*', () {
      expect(stripMarkdown('*italic*'), 'italic');
    });

    test('3. removes inline `code`', () {
      expect(stripMarkdown('`code`'), 'code');
    });

    test('4. replaces fenced code block with (code block)', () {
      const input = '```dart\nx\n```';
      expect(stripMarkdown(input), '(code block)');
    });

    test('5. extracts link text from [link](url)', () {
      expect(stripMarkdown('[click](https://x)'), 'click');
    });

    test('6. strips heading #', () {
      expect(stripMarkdown('# Heading'), 'Heading');
    });

    test('7. strips bullet marker', () {
      expect(stripMarkdown('- bullet'), 'bullet');
    });

    test('8. handles mixed inline markdown', () {
      expect(
        stripMarkdown('**hello** *world* and [a](b)'),
        'hello world and a',
      );
    });

    test('9. returns empty string for empty input', () {
      expect(stripMarkdown(''), '');
    });

    test('10. removes HTML tags', () {
      expect(stripMarkdown('Hello<br>World'), 'HelloWorld');
    });

    test('11. removes ~~strikethrough~~', () {
      expect(stripMarkdown('~~strike~~'), 'strike');
    });

    test('12. strips h2 and h3 headings', () {
      expect(stripMarkdown('## SubHeading'), 'SubHeading');
      expect(stripMarkdown('### Minor'), 'Minor');
    });

    test('13. strips numbered list marker', () {
      expect(stripMarkdown('1. first'), 'first');
      expect(stripMarkdown('2. second'), 'second');
    });

    test('14. removes __bold__ variant', () {
      expect(stripMarkdown('__bold__'), 'bold');
    });
  });
}
