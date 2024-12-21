@TestOn('vm')
library;

import 'dart:io';

import 'package:fs_shim/utils/io/read_write.dart';
import 'package:path/path.dart';
import 'package:process_run/process_run.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_prj.dart';
import 'package:test/test.dart';

Future<void> main() async {
  group('dtk', () {
    test('DtkProject create workspace and project', () async {
      var topDir = join('.dart_tool', 'tekartik_prj_tktools', 'test',
          'dtk_workspace_pubspec_overrides');
      var projectDir = join(topDir, 'packages', 'project');
      var prjTop = DtkProject(topDir);
      var prj = DtkProject(projectDir);
      await Directory(topDir).emptyOrCreate();
      await Directory(projectDir).create(recursive: true);
      await prjTop.createWorkspaceRootProject();
      await prj.createEmptyProject(projectName: 'tekartik_test_project1');
      await prj.createEmptyProject(projectName: 'tekartik_test_project2');
      await prj.createEmptyProject(projectName: 'tekartik_test_project3');
      await prj.addToWorkspace();
      var shell = Shell(workingDirectory: topDir);
      await shell.run('dart pub get --offline');
    });
  });
}
