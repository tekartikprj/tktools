@TestOn('vm')
library;

import 'dart:io';

import 'package:dev_build/build_support.dart';
import 'package:path/path.dart';
import 'package:process_run/shell.dart';
import 'package:test/test.dart';

void main() {
  var tkPubPath = normalize(absolute(join('example', 'tkpub.dart')));
  var configExportPath = normalize(absolute(join('.dart_tool',
      'tekartik_prj_tktools', 'test', 'test_tkpub', 'config_export.db')));
  var projectPath = normalize(absolute(join('.dart_tool',
      'tekartik_prj_tktools', 'test', 'test_tkpub', 'tkpub_test_project')));
  late Shell shell;
  setUp(() async {
    await Directory(dirname(configExportPath)).create(recursive: true);
    if (File(configExportPath).existsSync()) {
      await File(configExportPath).delete();
    }
    if (Directory(projectPath).existsSync()) {
      await Directory(projectPath).delete(recursive: true);
    }
    await Directory(projectPath).create(recursive: true);
    var shellEnvironment = ShellEnvironment()
      ..aliases['tkpub'] =
          'dart run ${shellArgument(tkPubPath)} --config-export-path ${shellArgument(configExportPath)}';
    shell = Shell(environment: shellEnvironment);
  });
  test('tkpub config get-export-path', () async {
    var path = (await shell.run('tkpub config get-export-path')).outText.trim();
    expect(path, configExportPath);
  });
  test('tkpub config get/set ref', () async {
    var gitRef = (await shell.run('tkpub config get-ref')).outText.trim();
    expect(gitRef, '<none>');
    await shell.run('tkpub config set-ref dart3a');
    gitRef = (await shell.run('tkpub config get-ref')).outText.trim();
    expect(gitRef, 'dart3a');
  });
  test('tkpub config get/set package', () async {
    try {
      await shell.run('tkpub config get demo');
      fail('should fail');
    } catch (e) {
      expect(e, isA<ShellException>());
    }
    await shell
        .run('tkpub config set demo --git-url url@git --git-path gitpath');
    var package = (await shell.run('tkpub config get demo')).outText.trim();
    expect(package, 'demo url@git gitpath');
  });
  test('tkpub add', () async {
    var prjShell = shell.cd(projectPath);

    await prjShell.run('tkpub config set-ref dart3a');
    // ["tekartik_firebase",{"gitPath":"firebase","gitUrl":"https://github.com/tekartik/firebase.dart"}]
    await shell.run(
        'tkpub config set tekartik_firebase --git-url https://github.com/tekartik/firebase.dart --git-path firebase');
    await prjShell.run('dart create -t console . --force');
    var pubspecYaml = await pathGetPubspecYamlMap(projectPath);
    expect(pubspecYamlHasAnyDependencies(pubspecYaml, ['tekartik_firebase']),
        isFalse);
    await prjShell.run('tkpub add tekartik_firebase');
    pubspecYaml = await pathGetPubspecYamlMap(projectPath);
    expect(pubspecYamlHasAnyDependencies(pubspecYaml, ['tekartik_firebase']),
        isTrue);
  });
}
