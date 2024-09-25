import 'dart:convert';
import 'dart:io';

export 'package:dev_build/src/content/lines.dart';
export 'package:dev_build/src/content/lines_io.dart';

var _eol = Platform.isWindows ? '\r\n' : '\n';

/// Convert a list of lines to a single string with line endings.
String linesToIoText(List<String> lines) {
  if (lines.isEmpty) {
    return '';
  }
  return '${lines.join(_eol)}$_eol';
}

/// Fix lines ending
String textToIoText(String text) {
  return linesToIoText(linesFromIoText(text));
}

/// Convert a single string with to a list of lines (ignoring line endings).
List<String> linesFromIoText(String text) => LineSplitter.split(text).toList();

/// Extension on [File] to read and write lines.
extension FileLinesIoFileExt on File {
  /// Read lines from a file.
  Future<List<String>> readLines() async {
    var lines = LineSplitter.split(await readAsString()).toList();
    return lines;
  }

  /// Write lines to a file.
  Future<void> writeLines(List<String> lines) async {
    await writeAsString(linesToIoText(lines));
  }
}
