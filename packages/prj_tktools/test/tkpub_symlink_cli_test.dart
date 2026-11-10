@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart';
import 'package:process_run/process_run.dart';
import 'package:test/test.dart';

/// `tkpub symlink` run as a sub process in a temp git tree, with the user
/// prefs in a temp folder (TEKARTIK_PROCESS_RUN_USER_APP_DATA_PATH).
void main() {
  late Directory tmp;
  late String githubTop;
  late String packagePath;
  late String export;
  late String appData;
  var cliScript = absolute(join('test', 'src', 'tkpub_cli_main.dart'));

  Future<ProcessResult> tkpub(
    List<String> arguments, {
    required String workingDirectory,
  }) {
    return runExecutableArguments(
      Platform.resolvedExecutable,
      [cliScript, '--config-export-path=$export', ...arguments],
      workingDirectory: workingDirectory,
      environment: {'TEKARTIK_PROCESS_RUN_USER_APP_DATA_PATH': appData},
    );
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tkpub_symlink_');
    appData = join(tmp.path, 'app_data');
    export = join(tmp.path, 'tkpub_export.jsonl');
    // The github top is the folder holding github.com/tekartik
    githubTop = join(tmp.path, 'git', 'github.com');
    packagePath = join(githubTop, 'tekartik', 'repo', 'a_pkg');
    await Directory(packagePath).create(recursive: true);
    await File(
      join(packagePath, 'pubspec.yaml'),
    ).writeAsString('name: a_pkg\n');
    await File(join(packagePath, 'work.txt')).writeAsString('uncommitted');
    var result = await tkpub([
      'config',
      'set',
      'a_pkg',
      '--git-url',
      'https://github.com/tekartik/repo',
      '--git-path',
      'a_pkg',
    ], workingDirectory: packagePath);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });
  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test(
    'symlink in a workspace, again',
    () async {
      var workspace = join(tmp.path, 'git', 'workspace');
      await Directory(workspace).create(recursive: true);
      var linkPath = join(workspace, 'tekartik', 'repo', 'a_pkg');
      for (var i = 0; i < 2; i++) {
        var result = await tkpub([
          'symlink',
          'a_pkg',
        ], workingDirectory: workspace);
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect(FileSystemEntity.isLinkSync(linkPath), isTrue);
        expect(Link(linkPath).targetSync(), packagePath);
      }
    },
    testOn: '!windows',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('symlink from the git top keeps the package', () async {
    var result = await tkpub(['symlink', 'a_pkg'], workingDirectory: githubTop);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('is not a link'));
    expect(FileSystemEntity.isLinkSync(packagePath), isFalse);
    expect(
      await File(join(packagePath, 'work.txt')).readAsString(),
      'uncommitted',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
