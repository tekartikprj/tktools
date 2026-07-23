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
      var topDir = join(
        '.dart_tool',
        'tekartik_prj_tktools',
        'test',
        'dtk_workspace_pubspec_overrides',
      );
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

    test('addAllProjectsToWorkspace skips sub-workspace and its tree', () async {
      var topDir = join(
        '.dart_tool',
        'tekartik_prj_tktools',
        'test',
        'dtk_sub_workspace_test',
      );
      var normalPrjDir = join(topDir, 'packages', 'normal_prj');
      var subWsDir = join(topDir, 'packages', 'sub_ws');
      var nestedPrjDir = join(subWsDir, 'packages', 'nested_prj');

      await Directory(topDir).emptyOrCreate();
      await Directory(normalPrjDir).create(recursive: true);
      await Directory(nestedPrjDir).create(recursive: true);

      var topPrj = DtkProject(topDir);
      await topPrj.createWorkspaceRootProject();

      await DtkProject(normalPrjDir).createEmptyProject(projectName: 'normal_prj');

      var subWsPrj = DtkProject(subWsDir);
      await subWsPrj.createWorkspaceRootProject();
      await DtkProject(nestedPrjDir).createEmptyProject(projectName: 'nested_prj');

      await topPrj.addAllProjectsToWorkspace();

      var pubspecContent = await File(join(topDir, 'pubspec.yaml')).readAsString();
      expect(pubspecContent, contains('packages/normal_prj'));
      expect(pubspecContent, isNot(contains('packages/sub_ws')));
      expect(pubspecContent, isNot(contains('packages/sub_ws/packages/nested_prj')));
    });
  });
}
