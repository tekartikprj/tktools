@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tekartik_prj_tktools/host_ci.dart';
import 'package:test/test.dart';

import 'host_ci_test_utils.dart';

void main() {
  group('model', () {
    test('enabled steps and policies', () {
      var project = DbHostCiProject();
      expect(project.enabledSteps, defaultSteps);
      expect(project.optionsSummary, isEmpty);
      project
        ..steps.v = ['test', 'analyze']
        ..pubGetOnly.v = true;
      expect(project.enabledSteps, [
        HostCiStepName.pubGet,
        HostCiStepName.analyze,
        HostCiStepName.testHost,
        HostCiStepName.testWeb,
      ]);
      project.skipPlatforms.v = ['web'];
      expect(project.enabledSteps, [
        HostCiStepName.pubGet,
        HostCiStepName.analyze,
        HostCiStepName.testHost,
      ]);
      expect(
        project.policyOf(HostCiStepName.buildWeb).policy,
        HostCiFailurePolicy.fail,
      );
      project.setPolicy(HostCiStepName.buildWeb, HostCiFailurePolicy.warn);
      project.setPolicy(
        HostCiStepName.analyzeDowngrade,
        HostCiFailurePolicy.accept,
      );
      expect(project.policyOf(HostCiStepName.buildWeb), (
        policy: HostCiFailurePolicy.warn,
        severity: HostCiSeverity.medium,
      ));
      // The downgrade analyze follows the downgrade policy.
      expect(
        project.policyOf(HostCiStepName.pubDowngrade).policy,
        HostCiFailurePolicy.accept,
      );
      expect(
        project.policyOf(HostCiStepName.analyzeDowngrade).policy,
        HostCiFailurePolicy.accept,
      );
      expect(
        () => project.setPolicy(
          HostCiStepName.pubUpgrade,
          HostCiFailurePolicy.warn,
        ),
        throwsArgumentError,
      );
      expect(
        project.optionsSummary,
        'pub get only, no format, no build host, no downgrade, skip web, '
        'build web: warn (medium), pub downgrade: accept',
      );
      project.setPolicy(HostCiStepName.buildWeb, HostCiFailurePolicy.fail);
      project.setPolicy(HostCiStepName.pubDowngrade, HostCiFailurePolicy.fail);
      expect(project.policies.v, isNull);
    });

    test('step names', () {
      expect(hostCiStepNameParse('downgrade'), HostCiStepName.pubDowngrade);
      expect(hostCiStepNameParse('pub-upgrade'), HostCiStepName.pubUpgrade);
      expect(
        hostCiStepNameParse('analyze downgrade'),
        HostCiStepName.analyzeDowngrade,
      );
      expect(hostCiStepNameParse('Format'), HostCiStepName.format);
      expect(hostCiStepNameParse('nope'), isNull);
      expect(hostCiPlatformFromName('chrome'), HostCiPlatform.web);
      expect(hostCiPlatformFromName('vm'), HostCiPlatform.host);
      expect(hostCiStepNamesParse('build'), [
        HostCiStepName.buildWeb,
        HostCiStepName.buildHost,
      ]);
      expect(hostCiStepNameParse('test-web'), HostCiStepName.testWeb);
      expect(hostCiStepNameParse('get'), HostCiStepName.pubGet);
      expect(
        hostCiNormalizeSteps([
          HostCiStepName.testWeb,
          HostCiStepName.analyzeDowngrade,
          HostCiStepName.analyze,
        ]),
        [
          HostCiStepName.analyze,
          HostCiStepName.testWeb,
          ...hostCiDowngradeSteps,
        ],
      );
    });

    test('open failure reports', () {
      DbHostCiRun run(HostCiRunStatus status, {bool validated = false}) =>
          DbHostCiRun()
            ..status.v = status.name
            ..validated.v = validated ? 1 : null;
      var interrupted = run(HostCiRunStatus.error)
        ..error.v = hostCiInterruptedError;
      var red1 = run(HostCiRunStatus.failure);
      var warning = run(HostCiRunStatus.warning);
      var red2 = run(HostCiRunStatus.failure);
      expect(
        hostCiOpenFailureRuns([
          run(HostCiRunStatus.failure),
          run(HostCiRunStatus.success),
          red1,
          run(HostCiRunStatus.cancelled),
          interrupted,
          warning,
          run(HostCiRunStatus.failure, validated: true),
          red2,
        ]),
        [red1, warning, red2],
      );
      expect(
        hostCiOpenFailureRuns([red1, run(HostCiRunStatus.success)]),
        isEmpty,
      );
    });
  });

  group('host ci', () {
    late Directory topDir;
    late String ciDir;
    late HostCi hostCi;
    var steps = <HostCiStepName, HostCiFakeProcess Function()>{};

    setUp(() async {
      topDir = newTempDir('host_ci');
      ciDir = p.join(topDir.path, 'host_ci');
      steps = {};
      hostCi = await openTestHostCi(
        ciDir,
        starter: fakeStarter(steps: steps),
        writeReport: true,
      );
    });

    tearDown(() async {
      await hostCi.close();
      deleteDir(topDir);
    });

    Future<DbHostCiProject> addRepo(String name) async {
      var path = p.join(topDir.path, name);
      await createGitRepo(path, remote: 'git@github.com:owner/$name.git');
      return await hostCi.addProject(path);
    }

    Future<DbHostCiRun> runRepo(String id) =>
        hostCi.run(id, trigger: HostCiTrigger.manual);

    test('a failure report is kept until validated or green', () async {
      var project = await addRepo('one');
      steps[HostCiStepName.testHost] = () => failingStep(command: 'dart test');
      var red1 = await runRepo(project.id);
      var red2 = await runRepo(project.id);
      var projects = await hostCi.getProjects();
      var status = projects[project.id]!;
      expect(status.openFailures.map((run) => run.id), [red1.id, red2.id]);
      expect(projects.failures.single.project.id, project.id);
      // Red and unchanged: due.
      expect(status.bucket, HostCiBucket.red);

      // Validated: closed, no longer proposed while unchanged.
      var validated = await hostCi.validate(project.id);
      expect(validated.map((run) => run.id), [red1.id, red2.id]);
      projects = await hostCi.getProjects();
      status = projects[project.id]!;
      expect(status.openFailures, isEmpty);
      expect(projects.failures, isEmpty);
      expect(status.bucket, HostCiBucket.fresh);
      expect(status.reason, startsWith('red (validated) '));

      // A new red one opens again, a green one closes it.
      await runRepo(project.id);
      expect((await hostCi.getProjects()).failures, hasLength(1));
      steps.remove(HostCiStepName.testHost);
      var green = await runRepo(project.id);
      expect(green.runStatus, HostCiRunStatus.success);
      expect((await hostCi.getProjects()).failures, isEmpty);
    });

    test('next: the oldest started wins within a bucket', () async {
      var one = await addRepo('one');
      var two = await addRepo('two');
      var three = await addRepo('three');
      var projects = await hostCi.getProjects();
      expect(projects.next!.project.id, one.id);
      await runRepo(one.id);
      await runRepo(two.id);
      steps[HostCiStepName.format] = () => failingStep(command: 'dart format');
      await runRepo(three.id);
      projects = await hostCi.getProjects();
      // The red one first, then fresh greens.
      expect(projects.statuses.map((status) => status.bucket), [
        HostCiBucket.red,
        HostCiBucket.fresh,
        HostCiBucket.fresh,
      ]);
      expect(projects.next!.project.id, three.id);
      // Changed: both due, the oldest started first.
      await commit(p.join(topDir.path, 'two'), 'two');
      await commit(p.join(topDir.path, 'one'), 'one');
      projects = await hostCi.getProjects();
      expect(projects.due.map((status) => status.project.id), [
        one.id,
        two.id,
        three.id,
      ]);
      expect(
        projects[one.id]!.reason,
        '1 commit since the green run of just '
        'now',
      );
      // Skipped: never proposed.
      await hostCi.setPaused(one.id, paused: true);
      projects = await hostCi.getProjects();
      expect(projects.next!.project.id, two.id);
      expect(projects.statuses.last.bucket, HostCiBucket.paused);
      expect(projects.statuses.last.bucket.label, 'skipped');
    });

    test('options', () async {
      var project = await addRepo('one');
      await hostCi.setPlatformSkipped(
        project.id,
        HostCiPlatform.web,
        skipped: true,
      );
      await hostCi.setStepPolicy(
        project.id,
        HostCiStepName.buildWeb,
        HostCiFailurePolicy.warn,
        severity: HostCiSeverity.low,
      );
      await hostCi.setProjectOptions(
        project.id,
        steps: [HostCiStepName.analyze, HostCiStepName.testHost],
        extraArgs: ['-i'],
        pubGetOnly: true,
      );
      var read = (await hostCi.store.getProject(project.id))!;
      expect(
        read.optionsSummary,
        'pub get only, no format, no build host, no downgrade, skip web, '
        'build web: warn (low), -i',
      );
      await hostCi.setProjectOptions(
        project.id,
        steps: null,
        extraArgs: null,
        pubGetOnly: false,
      );
      await hostCi.setPlatformSkipped(
        project.id,
        HostCiPlatform.web,
        skipped: false,
      );
      read = (await hostCi.store.getProject(project.id))!;
      expect(read.optionsSummary, 'build web: warn (low)');
    });

    test('report pages', () async {
      var project = await addRepo('one');
      steps[HostCiStepName.analyze] = () => failingStep(package: './pkg');
      var run = await runRepo(project.id);
      var report = hostCi.report;
      var index = File(report.indexPath).readAsStringSync();
      expect(index, contains('Failure reports (1)'));
      expect(index, contains('runs/${run.id}.html'));
      expect(index, contains('<code>./pkg</code>'));
      var runPage = File(report.runPath(run.id)).readAsStringSync();
      expect(runPage, contains('<details open><summary>'));
      expect(runPage, contains('=== analyze (2/10) ==='));
      expect(runPage, contains('<span class="err">'));
      var projectPage = File(report.projectPath(project.id)).readAsStringSync();
      expect(projectPage, contains('../runs/${run.id}.html'));
      // Validated: the index no longer lists it.
      await hostCi.validate(project.id);
      index = File(report.indexPath).readAsStringSync();
      expect(index, contains('Failure reports (0)'));
      expect(await report.writeAll(), report.indexPath);
    });

    test('changes of another process are seen', () async {
      var other = await openTestHostCi(ciDir, starter: fakeStarter());
      addTearDown(other.close);
      hostCi.startWatching(interval: const Duration(milliseconds: 20));
      var changed = hostCi.onChanged.first;
      var path = p.join(topDir.path, 'one');
      await createGitRepo(path);
      await other.addProject(path);
      await changed.timeout(const Duration(seconds: 5));
      expect((await hostCi.getProjects()).statuses, hasLength(1));
    });

    test('interrupted runs are recovered', () async {
      var project = await addRepo('one');
      await hostCi.store.addRun(
        DbHostCiRun()
          ..project.v = project.id
          ..status.v = HostCiRunStatus.running.name
          ..pid.v = 1
          ..start.v = 1000
          ..heartbeat.v = 2000,
      );
      var projects = await hostCi.getProjects();
      var run = projects[project.id]!.lastRun!;
      expect(run.runStatus, HostCiRunStatus.error);
      expect(run.isInterrupted, isTrue);
      expect(run.end.v, 2000);
      // Not a report, not a verdict.
      expect(projects[project.id]!.openFailures, isEmpty);
      expect(projects[project.id]!.bucket, HostCiBucket.neverRun);
    });

    test('log retention keeps the open reports', () async {
      await hostCi.setSettings(DbHostCiSettings()..logsKept.v = 1);
      var project = await addRepo('one');
      steps[HostCiStepName.analyze] = () => failingStep();
      var red = await runRepo(project.id);
      steps.remove(HostCiStepName.analyze);
      await runRepo(project.id);
      // Green: the red one is closed, its log can go.
      var runs = await hostCi.getRuns(project.id);
      expect(runs.first.log.v, isNull);
      expect(File(p.join(hostCi.logsDir, red.log.v!)).existsSync(), isFalse);
      steps[HostCiStepName.analyze] = () => failingStep();
      var red2 = await runRepo(project.id);
      var red3 = await runRepo(project.id);
      runs = await hostCi.getRuns(project.id);
      expect(runs.where((run) => run.log.v != null).map((run) => run.id), [
        red2.id,
        red3.id,
      ]);
    });
  });

  test('the queue: one run at a time on the machine, oldest first', () async {
    var topDir = newTempDir('queue');
    addTearDown(() => deleteDir(topDir));
    var script = p.absolute(p.join('test', 'src', 'host_ci_queue_main.dart'));
    var release = p.join(topDir.path, 'release');
    var output = <String>[];
    Future<Process> start(String name, {bool hold = false}) async {
      var process = await Process.start(Platform.resolvedExecutable, [
        script,
        topDir.path,
        name,
        if (hold) release,
      ]);
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(output.add);
      return process;
    }

    Future<void> until(FutureOr<bool> Function() condition) async {
      var end = DateTime.now().add(const Duration(seconds: 20));
      while (!await condition()) {
        if (DateTime.now().isAfter(end)) {
          fail('timeout, output: $output');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    var queue = HostCiRunQueue(topDir.path);
    // The first one holds the slot until released.
    var first = await start('first', hold: true);
    await until(() => output.contains('first acquired'));
    expect((await queue.readRunning())!.project, 'first');
    var second = await start('second');
    await until(() async => (await queue.readState()).waiting.length == 1);
    var third = await start('third');
    await until(() async => (await queue.readState()).waiting.length == 2);
    var state = await queue.readState();
    expect(state.running!.project, 'first');
    expect(state.waiting.map((entry) => entry.project), ['second', 'third']);
    File(release).writeAsStringSync('');
    expect(await first.exitCode, 0);
    expect(await second.exitCode, 0);
    expect(await third.exitCode, 0);
    expect(output.where((line) => line.endsWith('acquired')), [
      'first acquired',
      'second acquired',
      'third acquired',
    ]);
    expect((await queue.readState()).isEmpty, isTrue);

    // Killed while holding the slot: the next one runs anyway.
    File(release).deleteSync();
    output.clear();
    var killed = await start('killed', hold: true);
    await until(() => output.contains('killed acquired'));
    var after = await start('after');
    await until(() async => (await queue.readState()).waiting.length == 1);
    expect(output, isNot(contains('after acquired')));
    killed.kill(ProcessSignal.sigkill);
    expect(await after.exitCode, 0);
    expect(output, contains('after acquired'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
