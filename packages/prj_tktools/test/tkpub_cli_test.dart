@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart';
import 'package:test/test.dart';

/// tkpub command line tests, run as a sub process in a temp git tree, with
/// the user prefs in a temp folder (TEKARTIK_PROCESS_RUN_USER_APP_DATA_PATH).
void main() {
  late Directory tmp;
  late String repoPath;
  late String mainPath;
  late String export;
  late String appData;
  var cliScript = absolute(join('test', 'src', 'tkpub_cli_main.dart'));

  Future<ProcessResult> tkpub(
    List<String> arguments, {
    String? workingDirectory,
    bool configExportPath = true,
  }) {
    return Process.run(
      Platform.resolvedExecutable,
      [
        cliScript,
        if (configExportPath) '--config-export-path=$export',
        ...arguments,
      ],
      workingDirectory: workingDirectory ?? mainPath,
      environment: {'TEKARTIK_PROCESS_RUN_USER_APP_DATA_PATH': appData},
    );
  }

  Future<void> writePackage(
    String name, {
    List<String> dependencies = const [],
  }) async {
    var dir = Directory(join(repoPath, name));
    await dir.create(recursive: true);
    await File(join(dir.path, 'pubspec.yaml')).writeAsString(
      '''
name: $name
environment:
  sdk: ^3.0.0
${dependencies.isEmpty ? '' : 'dependencies:\n${dependencies.map((dependency) => '  $dependency:\n    path: ../$dependency\n').join()}'}''',
    );
  }

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('tkpub_cli_');
    appData = join(tmp.path, 'app_data');
    export = join(tmp.path, 'tkpub_export.jsonl');
    // The github top is the folder holding github.com/tekartik
    repoPath = join(tmp.path, 'git', 'github.com', 'tekartik', 'repo');
    mainPath = join(repoPath, 'main_pkg');
    for (var name in ['a_pkg', 'b_pkg', 'c_pkg', 'some_pkg']) {
      await writePackage(name);
    }
    await writePackage(
      'main_pkg',
      dependencies: ['a_pkg', 'b_pkg', 'c_pkg', 'some_pkg'],
    );
    await File(join(mainPath, 'pubspec_overrides.yaml')).writeAsString('''
dependency_overrides:
  a_pkg:
    path: ../a_pkg
  b_pkg:
    path: ../b_pkg
  c_pkg:
    path: ../c_pkg
''');
    await Process.run('git', ['init', '-q'], workingDirectory: repoPath);
    // Path dependencies only, offline.
    var result = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'get',
      '--offline',
    ], workingDirectory: mainPath);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });
  tearDownAll(() async {
    await tmp.delete(recursive: true);
  });

  test('remove --pubspec-overrides handles every package', () async {
    var result = await tkpub([
      'remove',
      '--pubspec-overrides',
      'a_pkg',
      'b_pkg',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    var overrides = await File(
      join(mainPath, 'pubspec_overrides.yaml'),
    ).readAsString();
    expect(overrides, isNot(contains('a_pkg')));
    expect(overrides, isNot(contains('b_pkg')));
    expect(overrides, contains('c_pkg'));
  });

  test('remove a dependency', () async {
    var result = await tkpub(['remove', 'some_pkg']);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(
      await File(join(mainPath, 'pubspec.yaml')).readAsString(),
      isNot(contains('some_pkg')),
    );
  });

  test('clear', () async {
    var overridesFile = File(join(mainPath, 'pubspec_overrides.yaml'));
    var result = await tkpub(['clear']);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(result.stderr, contains('Must specify --pubspec-overrides'));
    expect(overridesFile.existsSync(), isTrue);

    result = await tkpub(['clear', '--pubspec-overrides']);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(overridesFile.existsSync(), isFalse);
  });

  test('add --overrides', () async {
    var result = await tkpub(['add', '--overrides', 'unknown_pkg']);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Package not found unknown_pkg'));

    result = await tkpub(['add', '-p', '--dev', 'unknown_pkg']);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Cannot use --pubspec-overrides'));
  });

  test('init sets the config export path', () async {
    var newExport = join(tmp.path, 'new_export.jsonl');
    var result = await tkpub(['init', newExport], configExportPath: false);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    result = await tkpub([
      'config',
      'get-export-path',
    ], configExportPath: false);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect((result.stdout as String).trim(), newExport);
  });
}
