@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:dev_build/shell.dart';
import 'package:fs_shim/utils/io/read_write.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

extension on String {
  /// Get lines
  List<String> get lines => LineSplitter.split(this).toList();
}

Future<void> main() async {
  test('workspace pubspec overrides', () async {
    var workspacePubspec =
        '''
name: _
publish_to: none
environment:
  sdk: ^3.6.0
workspace:
  - packages/project
'''
            .lines;
    var projectPubspec =
        '''
name: tekartik_test_project1
publish_to: none
environment:
  sdk: ^3.6.0
resolution: workspace
'''
            .lines;
    var topDir = join(
      '.dart_tool',
      'tekartik_prj_tktools',
      'test',
      'workspace_pubspec_overrides',
    );
    var projectDir = join(topDir, 'packages', 'project');
    await Directory(topDir).emptyOrCreate();
    await File(join(topDir, 'pubspec.yaml')).writeLines(workspacePubspec);
    await File(join(projectDir, 'pubspec.yaml')).writeLines(projectPubspec);
    var shell = Shell(workingDirectory: topDir);
    await shell.run('dart pub get --offline');
  });
}
