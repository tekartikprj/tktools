@TestOn('vm')
library;

import 'package:process_run/stdio.dart';
import 'package:tekartik_prj_tktools/file_lines_io.dart';
import 'package:test/test.dart';

void main() {
  group('file_lines_io', () {
    test('linesTo/FromIoText', () {
      expect(linesToIoText([]), '');
      expect(linesFromIoText(''), <String>[]);
      expect(linesFromIoText(linesToIoText(['a', 'b'])), ['a', 'b']);
    });
    if (Platform.isWindows) {
      test('linesToIoText', () {
        expect(linesToIoText(['a', 'b']), 'a\r\nb\r\n');
      });
    } else {
      test('linesToIoText', () {
        expect(linesToIoText(['a', 'b']), 'a\nb\n');
      });
    }
  });
}
