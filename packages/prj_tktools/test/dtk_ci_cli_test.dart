@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tekartik_prj_tktools/src/bin/dtk_ci.dart';
import 'package:test/test.dart';

import 'host_ci/host_ci_test_utils.dart';

/// `dtk ci` command line tests, run as a sub process, the Host CI folder in a
/// temp folder (TEKARTIK_HOST_CI_DIR).
void main() {
  late Directory topDir;
  late String ciDir;
  late String repoPath;
  late String cliScript;

  Future<ProcessResult> dtk(List<String> arguments) => Process.run(
    Platform.resolvedExecutable,
    [cliScript, 'ci', ...arguments],
    environment: {'TEKARTIK_HOST_CI_DIR': ciDir},
  );

  Future<Object?> dtkJson(List<String> arguments) async {
    var result = await dtk([...arguments, '--json']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return jsonDecode(result.stdout as String);
  }

  setUpAll(() async {
    topDir = newTempDir('dtk_ci');
    ciDir = p.join(topDir.path, 'host_ci');
    repoPath = p.join(topDir.path, 'repo');
    await createGitRepo(repoPath, remote: 'git@github.com:owner/repo.git');
    // Compiled once: a sub process per command.
    cliScript = p.join(topDir.path, 'dtk.dill');
    var compile = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'kernel',
      p.join('test', 'src', 'dtk_cli_main.dart'),
      '-o',
      cliScript,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stderr}');
  });

  tearDownAll(() {
    deleteDir(topDir);
  });

  test('add, options, status', () async {
    var added = (await dtkJson(['add', repoPath])) as List;
    expect((added.single as Map)['id'], 'github.com/owner/repo');

    var result = await dtk(['steps', 'repo', 'analyze', 'test', 'downgrade']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      result.stdout,
      'github.com/owner/repo: pub upgrade -> analyze -> test host -> test web '
      '-> pub downgrade -> analyze downgrade -> pub restore\n',
    );
    result = await dtk(['skip', 'repo', '--platform', 'web']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    result = await dtk([
      'policy',
      'repo',
      'build',
      'warn',
      '--severity',
      'low',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      result.stdout,
      'github.com/owner/repo: no format, no build host, skip web, '
      'build web: warn (low), build host: warn (low)\n',
    );
    result = await dtk(['policy', 'repo', 'pub-get', 'warn']);
    expect(result.exitCode, 1);

    var statuses = (await dtkJson(['status'])) as List;
    var status = statuses.single as Map;
    expect(status['id'], 'github.com/owner/repo');
    expect(status['bucket'], 'neverRun');
    expect(status['next'], isTrue);
    expect(status['steps'], [
      'pubUpgrade',
      'analyze',
      'testHost',
      'pubDowngrade',
      'analyzeDowngrade',
      'pubRestore',
    ]);
    var next = (await dtkJson(['next'])) as Map;
    expect(next['id'], 'github.com/owner/repo');
    expect(await dtkJson(['failures']), isEmpty);
    var queue = (await dtkJson(['queue'])) as Map;
    expect(queue['running'], isNull);

    result = await dtk(['skip', 'repo']);
    expect(result.exitCode, 0);
    expect(await dtkJson(['next']), isNull);
    result = await dtk(['unskip', 'repo']);
    expect(result.exitCode, 0);

    result = await dtk(['report']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    var index = (result.stdout as String).trim();
    expect(index, p.join(ciDir, 'report', 'index.html'));
    expect(File(index).readAsStringSync(), contains('github.com/owner/repo'));

    result = await dtk(['status', 'nope']);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('No Host CI project matches "nope"'));
  });

  /// True when the real run_ci can run (dev_build activated).
  Future<bool> runCiActivated() async {
    var version = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'global',
      'run',
      'dev_build:run_ci',
      '--version',
    ]);
    if (version.exitCode != 0) {
      markTestSkipped('dev_build not activated');
      return false;
    }
    return true;
  }

  test('run one step for real', () async {
    // The real run_ci (an empty checkout: nothing to analyze, fast).
    if (!await runCiActivated()) {
      return;
    }
    var runs = (await dtkJson(['run', 'repo', '--step', 'analyze'])) as List;
    var run = runs.single as Map;
    expect(run['status'], 'success', reason: '$run');
    expect((run['steps'] as List).map((step) => (step as Map)['name']), [
      'analyze',
    ]);
    var result = await dtk(['log', 'repo', '--step', 'analyze']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('=== analyze (1/1) ==='));
    // A retry only: never a verdict.
    var status = ((await dtkJson(['status', 'repo'])) as List).single as Map;
    expect(status['bucket'], 'neverRun');
    expect(
      File(p.join(ciDir, 'report', 'runs', '${run['id']}.html')).existsSync(),
      isTrue,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('run --next <n>', () async {
    expect(dtkCiNextCount([]), 1);
    expect(dtkCiNextCount(['3']), 3);
    for (var rest in [
      ['0'],
      ['repo'],
      ['2', 'repo'],
    ]) {
      expect(() => dtkCiNextCount(rest), throwsArgumentError, reason: '$rest');
    }
    var result = await dtk(['run', '--next', 'repo']);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('--next [<n>]'));
    result = await dtk(['run', '--next', '2', '--all-due']);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('--next or --all-due'));

    if (!await runCiActivated()) {
      return;
    }
    // Two empty checkouts, pub upgrade and analyze only (fast).
    var otherPath = p.join(topDir.path, 'other');
    await createGitRepo(otherPath, remote: 'git@github.com:owner/other.git');
    result = await dtk(['add', otherPath]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    for (var project in ['repo', 'other']) {
      result = await dtk(['steps', project, 'analyze']);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }
    // 3 asked, 2 due: each runs once.
    var runs = ((await dtkJson(['run', '--next', '3'])) as List).cast<Map>();
    expect(runs.map((run) => run['project']).toSet(), {
      'github.com/owner/repo',
      'github.com/owner/other',
    });
    expect(runs.map((run) => run['trigger']), ['next', 'next']);
    expect(runs.map((run) => run['status']), ['success', 'success']);
    // Nothing due any more.
    expect(await dtkJson(['run', '--next', '2']), isEmpty);
    result = await dtk(['run', '--next']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, 'Nothing due\n');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
