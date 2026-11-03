@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tekartik_prj_tktools/host_ci.dart';
import 'package:test/test.dart';

import 'host_ci_test_utils.dart';

void main() {
  late Directory topDir;
  late String repoPath;
  late String ciDir;
  HostCi? hostCi;

  setUp(() async {
    topDir = newTempDir('runner');
    repoPath = p.join(topDir.path, 'repo');
    ciDir = p.join(topDir.path, 'host_ci');
    await createGitRepo(
      repoPath,
      remote: 'git@github.com:owner/repo.git',
      flutterApp: true,
    );
  });

  tearDown(() async {
    await hostCi?.close();
    hostCi = null;
    deleteDir(topDir);
  });

  Future<HostCi> open(HostCiFakeProcessStarter starter) async =>
      hostCi = await openTestHostCi(ciDir, starter: starter);

  Future<DbHostCiRun> runOnce(
    HostCiFakeProcessStarter starter, {
    void Function(DbHostCiProject project)? options,
    List<HostCiOutputLine>? lines,
  }) async {
    var hostCi = await open(starter);
    var project = await hostCi.addProject(repoPath);
    if (options != null) {
      await hostCi.store.updateProject(project.id, options);
    }
    return await hostCi.run(
      project.id,
      trigger: HostCiTrigger.manual,
      onLines: lines?.addAll,
    );
  }

  test('all green, the steps in order', () async {
    var starter = fakeStarter();
    var lines = <HostCiOutputLine>[];
    var run = await runOnce(starter, lines: lines);

    expect(run.runStatus, HostCiRunStatus.success);
    expect(run.project.v, 'github.com/owner/repo');
    expect(run.head.v, hasLength(40));
    expect(run.branch.v, 'main');
    expect(run.dirty.v, 0);
    expect(run.dartVersion.v, '3.13.7');
    expect(run.runCiVersion.v, '1.1.17');
    expect(run.client.v, 'test');
    expect(run.pid.v, pid);
    expect(run.stepList.map((step) => step.stepName), defaultSteps);
    expect(
      run.stepList.map((step) => step.stepStatus),
      everyElement(HostCiStepStatus.success),
    );
    expect(startedSteps(starter), defaultSteps);
    String argsOf(HostCiStepName step) => starter.starts
        .firstWhere((start) => stepOfArguments(start.arguments) == step)
        .arguments
        .join(' ');
    expect(
      argsOf(HostCiStepName.pubUpgrade),
      'pub global run dev_build:run_ci --pub-upgrade --recursive',
    );
    expect(
      argsOf(HostCiStepName.analyze),
      'pub global run dev_build:run_ci --analyze --no-pub-get --recursive',
    );
    expect(
      argsOf(HostCiStepName.pubDowngrade),
      'pub global run dev_build:run_ci --pub-downgrade --no-override '
      '--recursive',
    );
    // run_ci 1.1.17 has no --no-fatal-warnings: dropped, said.
    expect(
      argsOf(HostCiStepName.analyzeDowngrade),
      'pub global run dev_build:run_ci --analyze --no-pub-get --no-override '
      '--recursive',
    );
    expect(
      lines.map((line) => line.text),
      contains(
        '# run_ci 1.1.17 has no --no-fatal-warnings (1.1.17+3): the warnings '
        'of the analyze downgrade are fatal, update it: dart pub global '
        'activate dev_build',
      ),
    );
    expect(
      argsOf(HostCiStepName.pubRestore),
      'pub global run dev_build:run_ci --pub-get --no-override --recursive',
    );

    // Saved, the log written.
    var saved = (await hostCi!.getRun(run.id))!;
    expect(saved.runStatus, HostCiRunStatus.success);
    expect(saved.end.v, isNotNull);
    var logLines = File(p.join(hostCi!.logsDir, run.log.v!)).readAsLinesSync();
    expect(logLines, contains('=== pub upgrade (1/10) ==='));
    expect(logLines, contains('=== analyze (2/10) ==='));
    expect(logLines, contains('=== pub restore (10/10) ==='));
    expect(logLines.last, startsWith('=== success, '));
    expect(lines.map((line) => line.text), contains('=== format (3/10) ==='));
    // The slot is given back.
    expect((await hostCi!.getQueue()).isEmpty, isTrue);
  });

  test('analyze downgrade: errors only from run_ci 1.1.17+3', () async {
    var starter = fakeStarter(runCiVersion: '1.1.17+3');
    var lines = <HostCiOutputLine>[];
    var run = await runOnce(starter, lines: lines);
    expect(run.runStatus, HostCiRunStatus.success);
    expect(startedSteps(starter), defaultSteps);
    expect(
      starter.starts
          .firstWhere(
            (start) =>
                stepOfArguments(start.arguments) ==
                HostCiStepName.analyzeDowngrade,
          )
          .arguments
          .join(' '),
      'pub global run dev_build:run_ci --analyze --no-pub-get --no-override '
      '--no-fatal-warnings --recursive',
    );
    expect(
      lines.map((line) => line.text),
      isNot(contains(startsWith('# run_ci 1.1.17+3 has no'))),
    );
    expect(hostCiRunCiHasNoFatalWarnings('1.1.17+2'), isFalse);
    expect(hostCiRunCiHasNoFatalWarnings('1.1.15'), isFalse);
    expect(hostCiRunCiHasNoFatalWarnings('1.1.18'), isTrue);
    expect(hostCiRunCiHasNoFatalWarnings(null), isTrue);
  });

  test('a red step skips the following ones', () async {
    var starter = fakeStarter(
      steps: {HostCiStepName.analyze: () => failingStep(package: './app')},
    );
    var run = await runOnce(starter);
    expect(run.runStatus, HostCiRunStatus.failure);
    expect(startedSteps(starter), [
      HostCiStepName.pubUpgrade,
      HostCiStepName.analyze,
    ]);
    expect(run.stepList.map((step) => step.stepStatus), [
      HostCiStepStatus.success,
      HostCiStepStatus.failure,
      for (var i = 0; i < 8; i++) HostCiStepStatus.skipped,
    ]);
    var failed = run.failedStep!;
    expect(failed.stepName, HostCiStepName.analyze);
    expect(failed.failedPackage.v, './app');
    expect(failed.failedCommand.v, 'dart analyze');
    expect(run.isFailureReport, isTrue);
  });

  test('pub get only, steps off, skipped platforms', () async {
    var starter = fakeStarter();
    var run = await runOnce(
      starter,
      options: (project) => project
        ..pubGetOnly.v = true
        // The name of the first versions: both test steps.
        ..steps.v = ['analyze', 'test']
        ..skipPlatforms.v = ['web'],
    );
    expect(run.runStatus, HostCiRunStatus.success);
    expect(startedSteps(starter), [
      HostCiStepName.pubGet,
      HostCiStepName.analyze,
      HostCiStepName.testHost,
    ]);
    var testArgs = starter.starts
        .firstWhere(
          (start) =>
              stepOfArguments(start.arguments) == HostCiStepName.testHost,
        )
        .arguments;
    expect(
      testArgs.join(' '),
      'pub global run dev_build:run_ci --vm-test --no-pub-get --recursive',
    );
  });

  test('a warned build: a warning, the next steps run', () async {
    var starter = fakeStarter(
      steps: {HostCiStepName.buildWeb: () => failingStep(command: 'flutter')},
    );
    var run = await runOnce(
      starter,
      options: (project) => project.setPolicy(
        HostCiStepName.buildWeb,
        HostCiFailurePolicy.warn,
        severity: HostCiSeverity.high,
      ),
    );
    expect(run.runStatus, HostCiRunStatus.warning);
    expect(run.warningSeverity, HostCiSeverity.high);
    expect(startedSteps(starter), defaultSteps);
    var build = run.failedStep!;
    expect(build.stepName, HostCiStepName.buildWeb);
    expect(build.isWarning, isTrue);
    expect(build.statusLabel, 'warning (high)');
    expect(hostCiRunStatusText(run), 'warning (high)');
    expect(run.isFailureReport, isTrue);
  });

  test('an accepted build: green', () async {
    var starter = fakeStarter(
      steps: {HostCiStepName.buildWeb: () => failingStep(command: 'flutter')},
    );
    var run = await runOnce(
      starter,
      options: (project) => project.setPolicy(
        HostCiStepName.buildWeb,
        HostCiFailurePolicy.accept,
      ),
    );
    expect(run.runStatus, HostCiRunStatus.success);
    expect(run.stepList[5].isAcceptedFailure, isTrue);
    expect(run.stepList[5].statusLabel, 'accepted');
    expect(run.failedStep, isNull);
    expect(startedSteps(starter), defaultSteps);
  });

  test('the downgrade is undone, even when red', () async {
    var lockPath = p.join(repoPath, 'pubspec.lock');
    var appLockPath = p.join(repoPath, 'app', 'pubspec.lock');
    var newLockPath = p.join(repoPath, 'other', 'pubspec.lock');
    File(lockPath).writeAsStringSync('upgraded');
    File(appLockPath)
      ..parent.createSync()
      ..writeAsStringSync('app upgraded');
    Directory(p.dirname(newLockPath)).createSync();
    // Never searched.
    var ignoredLockPath = p.join(repoPath, 'build', 'pubspec.lock');
    File(ignoredLockPath)
      ..parent.createSync()
      ..writeAsStringSync('build');
    String? lockDuringRestore;
    var starter = fakeStarter(
      steps: {
        HostCiStepName.pubDowngrade: () {
          File(lockPath).writeAsStringSync('downgraded');
          File(appLockPath).writeAsStringSync('app downgraded');
          File(newLockPath).writeAsStringSync('new');
          return HostCiFakeProcess(exitCode: 0);
        },
        HostCiStepName.analyzeDowngrade: () => failingStep(),
        HostCiStepName.pubRestore: () {
          lockDuringRestore = File(lockPath).readAsStringSync();
          return HostCiFakeProcess(exitCode: 0);
        },
      },
    );
    var run = await runOnce(starter);
    expect(run.runStatus, HostCiRunStatus.failure);
    expect(run.failedStep!.stepName, HostCiStepName.analyzeDowngrade);
    expect(startedSteps(starter), defaultSteps);
    expect(run.stepList.last.stepStatus, HostCiStepStatus.success);
    // Put back before the pub get of the restore.
    expect(lockDuringRestore, 'upgraded');
    expect(File(lockPath).readAsStringSync(), 'upgraded');
    expect(File(appLockPath).readAsStringSync(), 'app upgraded');
    expect(File(newLockPath).existsSync(), isFalse);
    expect(File(ignoredLockPath).readAsStringSync(), 'build');
  });

  test('a red pub downgrade still restores', () async {
    var lockPath = p.join(repoPath, 'pubspec.lock');
    File(lockPath).writeAsStringSync('upgraded');
    var starter = fakeStarter(
      steps: {
        HostCiStepName.pubDowngrade: () {
          File(lockPath).writeAsStringSync('half downgraded');
          return failingStep(command: 'dart pub downgrade');
        },
      },
    );
    var run = await runOnce(starter);
    expect(run.runStatus, HostCiRunStatus.failure);
    expect(startedSteps(starter), [
      ...defaultSteps.sublist(0, 8),
      HostCiStepName.pubRestore,
    ]);
    expect(run.stepList[8].stepStatus, HostCiStepStatus.skipped);
    expect(File(lockPath).readAsStringSync(), 'upgraded');
  });

  test('cancel during the downgrade restores the lock files', () async {
    var lockPath = p.join(repoPath, 'pubspec.lock');
    File(lockPath).writeAsStringSync('upgraded');
    late HostCiFakeProcess analyzeDowngrade;
    var starter = fakeStarter(
      steps: {
        HostCiStepName.pubDowngrade: () {
          File(lockPath).writeAsStringSync('downgraded');
          return HostCiFakeProcess(exitCode: 0);
        },
        HostCiStepName.analyzeDowngrade: () =>
            analyzeDowngrade = HostCiFakeProcess(),
      },
      onStep: (step) {
        if (step == HostCiStepName.analyzeDowngrade) {
          Future<void>.delayed(
            const Duration(milliseconds: 50),
            () => hostCi!.cancel(),
          );
        }
      },
    );
    var run = await runOnce(starter);
    expect(run.runStatus, HostCiRunStatus.cancelled);
    expect(analyzeDowngrade.killCount, 1);
    expect(run.stepList.last.stepStatus, HostCiStepStatus.cancelled);
    expect(File(lockPath).readAsStringSync(), 'upgraded');
  });

  test('run_ci not found: error', () async {
    var run = await runOnce(fakeStarter(runCiFound: false));
    expect(run.runStatus, HostCiRunStatus.error);
    expect(run.error.v, contains('run_ci not found'));
    expect(run.isFailureReport, isTrue);
  });

  test('folder gone: error', () async {
    var hostCi = await open(fakeStarter());
    var project = await hostCi.addProject(repoPath);
    deleteDir(Directory(repoPath));
    var run = await hostCi.run(project.id, trigger: HostCiTrigger.manual);
    expect(run.runStatus, HostCiRunStatus.error);
    expect(run.error.v, startsWith('Folder not found'));
  });

  test('one run at a time in a process', () async {
    late HostCiFakeProcess pubUpgrade;
    var hostCi = await open(
      fakeStarter(
        steps: {
          HostCiStepName.pubUpgrade: () => pubUpgrade = HostCiFakeProcess(),
        },
      ),
    );
    var project = await hostCi.addProject(repoPath);
    var future = hostCi.run(project.id, trigger: HostCiTrigger.manual);
    while (!hostCi.isRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    // The slot is held by this process, the run is live.
    var queue = await hostCi.getQueue();
    expect(queue.running!.project, project.id);
    expect(queue.running!.pid, pid);
    expect(
      () => hostCi.run(project.id, trigger: HostCiTrigger.manual),
      throwsStateError,
    );
    // Not interrupted by a recovery while it runs.
    expect(await hostCi.recoverInterruptedRuns(), isEmpty);
    while (!startedSteps(
      hostCi.starter as HostCiFakeProcessStarter,
    ).contains(HostCiStepName.pubUpgrade)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    pubUpgrade.exit(0);
    var run = await future;
    expect(run.runStatus, HostCiRunStatus.success);
  });

  group('build host', () {
    var platform = hostCiHostBuildPlatform!;

    test('packages', () async {
      var root = p.join(topDir.path, 'packages');
      createFlutterApp(root);
      createFlutterApp(p.join(root, 'example'));
      createFlutterApp(p.join(root, 'packages', 'no_main'), main: false);
      createFlutterApp(p.join(root, 'packages', 'no_platform'), platforms: []);
      createFlutterApp(p.join(root, 'packages', 'dart_only'), flutter: false);
      // Never searched, like run_ci: the test, build and hidden folders.
      createFlutterApp(p.join(root, 'test', 'fixture'));
      createFlutterApp(p.join(root, 'build', 'app'));
      createFlutterApp(p.join(root, '.hidden', 'app'));
      expect(await hostCiHostBuildPackages(root, platform), ['.', 'example']);
      expect(hostCiHostBuildArguments(platform), [
        'build',
        platform,
        '--no-pub',
      ]);
      expect(
        hostCiStepOfArguments(hostCiHostBuildArguments(platform)),
        HostCiStepName.buildHost,
      );
    });

    test('flutter build in each flutter app, all after a failure', () async {
      createFlutterApp(p.join(repoPath, 'flutter_app', 'example'));
      var builds = 0;
      var starter = fakeStarter(
        steps: {
          // The first app fails, the second one still builds.
          HostCiStepName.buildHost: () => ++builds == 1
              ? HostCiFakeProcess(err: ['Build process failed'], exitCode: 1)
              : HostCiFakeProcess(out: ['built'], exitCode: 0),
        },
      );
      var lines = <HostCiOutputLine>[];
      var run = await runOnce(
        starter,
        lines: lines,
        options: (project) => project.setPolicy(
          HostCiStepName.buildHost,
          HostCiFailurePolicy.warn,
        ),
      );
      expect(run.runStatus, HostCiRunStatus.warning);
      var hostBuilds = starter.starts
          .where((start) => start.executable == 'flutter')
          .toList();
      expect(hostBuilds.map((start) => start.workingDirectory), [
        p.join(repoPath, 'flutter_app'),
        p.join(repoPath, 'flutter_app', 'example'),
      ]);
      expect(hostBuilds.first.arguments, ['build', platform, '--no-pub']);
      var step = run.stepList[6];
      expect(step.stepName, HostCiStepName.buildHost);
      expect(step.stepStatus, HostCiStepStatus.failure);
      expect(step.exitCode.v, 1);
      expect(step.failedPackage.v, 'flutter_app');
      expect(step.failedCommand.v, 'flutter build $platform --no-pub');
      expect(
        lines.map((line) => line.text),
        containsAllInOrder([
          '=== build host (7/10) ===',
          '# package: flutter_app',
          '\$ flutter build $platform --no-pub',
          '# package: flutter_app/example',
        ]),
      );
    });

    test('nothing to build', () async {
      File(p.join(repoPath, 'flutter_app', 'lib', 'main.dart')).deleteSync();
      var starter = fakeStarter();
      var lines = <HostCiOutputLine>[];
      var run = await runOnce(starter, lines: lines);
      expect(run.runStatus, HostCiRunStatus.success);
      expect(startedSteps(starter), [
        for (var step in defaultSteps)
          if (step != HostCiStepName.buildHost) step,
      ]);
      expect(run.stepList[6].stepStatus, HostCiStepStatus.success);
      expect(
        lines.map((line) => line.text),
        contains('# no flutter app with $platform/ and lib/main.dart'),
      );
    });
  });

  test('retry: only a step, from a step', () async {
    var steps = <HostCiStepName, HostCiFakeProcess Function()>{
      HostCiStepName.format: () => failingStep(command: 'dart format'),
    };
    var starter = fakeStarter(steps: steps);
    var hostCi = await open(starter);
    var project = await hostCi.addProject(repoPath);
    var red = await hostCi.run(project.id, trigger: HostCiTrigger.manual);
    expect(red.failedStep!.stepName, HostCiStepName.format);

    // Only format: never a verdict, the report stays.
    starter.starts.clear();
    var only = await hostCi.run(
      project.id,
      trigger: HostCiTrigger.retry,
      only: [HostCiStepName.format],
    );
    expect(only.partialValue, HostCiPartial.only);
    expect(only.trigger.v, 'retry');
    expect(startedSteps(starter), [HostCiStepName.format]);
    steps.remove(HostCiStepName.format);
    only = await hostCi.run(
      project.id,
      trigger: HostCiTrigger.retry,
      only: [HostCiStepName.format],
    );
    expect(only.isGreen, isTrue);
    var status = (await hostCi.getProjects())[project.id]!;
    expect(status.openFailures.map((run) => run.id), [red.id]);
    expect(status.lastCompletedRun!.id, red.id);

    // From a step after the failed one: does not close the report.
    starter.starts.clear();
    await hostCi.run(
      project.id,
      trigger: HostCiTrigger.retry,
      from: HostCiStepName.testHost,
    );
    expect(startedSteps(starter), defaultSteps.sublist(3));
    status = (await hostCi.getProjects())[project.id]!;
    expect(status.openFailures, hasLength(1));

    // From the failed step: green, closes it.
    var from = await hostCi.run(
      project.id,
      trigger: HostCiTrigger.retry,
      from: HostCiStepName.format,
    );
    expect(from.partialValue, HostCiPartial.from);
    expect(from.stepList.map((step) => step.stepName), defaultSteps.sublist(2));
    status = (await hostCi.getProjects())[project.id]!;
    expect(status.openFailures, isEmpty);
    expect(status.lastCompletedRun!.id, from.id);

    // A downgrade step brings the three.
    starter.starts.clear();
    await hostCi.run(
      project.id,
      trigger: HostCiTrigger.retry,
      only: [HostCiStepName.analyzeDowngrade],
    );
    expect(startedSteps(starter), hostCiDowngradeSteps);
  });
}
