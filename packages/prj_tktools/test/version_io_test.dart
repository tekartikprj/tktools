import 'dart:io';

import 'package:path/path.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/version_io.dart';
import 'package:test/test.dart';

var testDir = Directory(join('.dart_tool', 'tekartik_prj_tktools_test_dir'))
  ..createSync(recursive: true);
void main() {
  test('pathVersionSet', () async {
    var path = join(testDir.path, 'version_io');
    Directory(path).createSync(recursive: true);
    File(join(path, 'pubspec.yaml')).writeAsStringSync('version: 1.0.0');
    expect(await pathVersionGet(path: path), Version.parse('1.0.0'));
    await pathVersionSet(path: path, version: Version.parse('1.0.1'));
    expect(await pathVersionGet(path: path), Version.parse('1.0.1'));
    await pathVersionBump(path: path);
    expect(await pathVersionGet(path: path), Version.parse('1.0.2'));
  });
}
