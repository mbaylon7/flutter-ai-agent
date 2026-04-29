import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/domain/markdown/tool_label.dart';

void main() {
  group('labelForTool', () {
    test('1. known web_search names map correctly', () {
      expect(labelForTool('web_search'), 'Searched the web');
      expect(labelForTool('webSearch'), 'Searched the web');
      expect(labelForTool('searchWeb'), 'Searched the web');
    });

    test('2. known file / command / code names map correctly', () {
      expect(labelForTool('read_url'), 'Read a webpage');
      expect(labelForTool('fetchUrl'), 'Read a webpage');
      expect(labelForTool('webFetch'), 'Read a webpage');
      expect(labelForTool('read_file'), 'Read a file');
      expect(labelForTool('readFile'), 'Read a file');
      expect(labelForTool('bash'), 'Ran a command');
      expect(labelForTool('runCommand'), 'Ran a command');
      expect(labelForTool('shell'), 'Ran a command');
      expect(labelForTool('python'), 'Ran some code');
      expect(labelForTool('runPython'), 'Ran some code');
    });

    test('3. snake_case fallback prettifies to "Used <words>"', () {
      expect(labelForTool('db_query'), 'Used db query');
      expect(labelForTool('send_email'), 'Used send email');
    });

    test('4. empty input returns "Used something"', () {
      expect(labelForTool(''), 'Used something');
    });
  });
}
