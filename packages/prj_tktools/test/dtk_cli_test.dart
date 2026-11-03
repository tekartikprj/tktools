@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_prj_tktools/dtk.dart'
    show DbDtkGitRepository, dtkGitConfigDbAction;
import 'package:tekartik_prj_tktools/src/dtk/dtk_git_config_db.dart'
    show dtkGitDbRepositoryStore;
import 'package:test/test.dart';

import 'src/dtk_test_tree.dart';
import 'src/test_kernel.dart';

/// dtk command line tests, run as a sub process on a temp git tree, with the
/// user prefs in a temp folder (TEKARTIK_PROCESS_RUN_USER_APP_DATA_PATH).
void main() {
  late DtkTestTree tree;
  // Compiled once: each call starts fast.
  late String cliProgram;

  Future<ProcessResult> dtk(List<String> arguments) {
    return Process.run(
      Platform.resolvedExecutable,
      [
        cliProgram,
        '--git-top=${tree.gitTop}',
        '--git-config-export-path=${tree.gitExport}',
        '--pub-config-export-path=${tree.pubExport}',
        ...arguments,
      ],
      environment: {'TEKARTIK_PROCESS_RUN_USER_APP_DATA_PATH': tree.tmp.path},
    );
  }

  Future<Object?> dtkJson(List<String> arguments) async {
    var result = await dtk([...arguments, '--json']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return jsonDecode(result.stdout as String);
  }

  setUpAll(() async {
    tree = await DtkTestTree.create();
    cliProgram = await compileTestScript(
      absolute(join('test', 'src', 'dtk_cli_main.dart')),
      tree.tmp.path,
    );
  });

  tearDownAll(() async {
    await tree.delete();
  });

  test('repos', () async {
    var repos = (await dtkJson(['repos'])) as List;
    expect(repos.map((repo) => (repo as Map)['id']), hasLength(4));
    repos = (await dtkJson(['repos', '--tag', 'public && !main'])) as List;
    expect(repos.map((repo) => (repo as Map)['id']), [
      'github.com/tekartik/sembast.dart',
    ]);
    var result = await dtk(['repos']);
    expect(
      (result.stdout as String).split('\n'),
      contains('github.com/tekartik/missing.dart  (not cloned)'),
    );
  });

  test('repo', () async {
    var repo = (await dtkJson(['repo', 'sembast'])) as Map;
    expect(repo['id'], 'github.com/tekartik/sembast.dart');
    expect(repo['packages'], ['sembast']);

    var result = await dtk(['repo', 'cv.dart']);
    expect(result.exitCode, 1);
    expect(
      result.stderr,
      contains(
        'Ambiguous repository cv.dart: github.com/fork/cv.dart, '
        'github.com/tekartik/cv.dart',
      ),
    );
    result = await dtk(['repo', 'none']);
    expect(result.exitCode, 1);
    expect((result.stderr as String).trim(), 'Repository not found: none');
  });

  test('packages and package', () async {
    var packages = (await dtkJson(['packages', '--published'])) as List;
    expect(packages.map((package) => (package as Map)['name']), ['cv']);
    packages = (await dtkJson(['packages', '--repo', 'sembast'])) as List;
    expect(packages.map((package) => (package as Map)['name']), ['sembast']);
    var package = (await dtkJson(['package', 'cv'])) as Map;
    expect(
      package['path'],
      tree.gitTopPath('github.com/tekartik/cv.dart/packages/cv'),
    );
    var result = await dtk(['package', 'none']);
    expect(result.exitCode, 1);
  });

  test('path', () async {
    var result = await dtk(['path', 'cv']);
    expect(
      (result.stdout as String).trim(),
      tree.gitTopPath('github.com/tekartik/cv.dart/packages/cv'),
    );
    result = await dtk(['path', 'tekartik/cv.dart']);
    expect(
      (result.stdout as String).trim(),
      tree.gitTopPath('github.com/tekartik/cv.dart'),
    );
    result = await dtk(['path', 'missing']);
    expect(
      (result.stdout as String).trim(),
      tree.gitTopPath('github.com/tekartik/missing.dart'),
    );
    expect(result.stderr, contains('is not cloned'));
  });

  test('sync', () async {
    var sync = (await dtkJson(['sync'])) as Map;
    expect(sync['missing'], ['github.com/tekartik/missing.dart']);
    expect(sync['unregistered'], ['github.com/other/unregistered']);
  });

  test('sync --clone', () async {
    // Local repositories registered under github.com ids (offline): a bare
    // one that clones and a missing one that fails.
    var origin = join(tree.tmp.path, 'origin.git');
    await Process.run('git', ['init', '-q', '--bare', origin]);
    await dtkGitConfigDbAction<void>(
      (db) async {
        for (var (id, gitUrl) in [
          ('github.com/local/cloneme', origin),
          ('github.com/local/broken', join(tree.tmp.path, 'none.git')),
        ]) {
          await dtkGitDbRepositoryStore
              .record(id)
              .put(
                db.database,
                DbDtkGitRepository()
                  ..gitUrl.v = gitUrl
                  ..tags.v = ['local'],
              );
        }
      },
      write: true,
      configExportPath: tree.gitExport,
    );
    var result = await dtk(['sync', '--tag', 'local', '--clone', '--json']);
    var sync = jsonDecode(result.stdout as String) as Map;
    expect(sync['cloned'], ['github.com/local/cloneme']);
    expect((sync['failed'] as Map).keys, ['github.com/local/broken']);
    expect(sync['missing'], ['github.com/local/broken']);
    expect(result.exitCode, 1);
    expect(
      Directory(tree.gitTopPath('github.com/local/cloneme/.git')).existsSync(),
      isTrue,
    );
  });
}
