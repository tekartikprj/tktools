@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tekartik_prj_tktools/host_ci.dart';
import 'package:test/test.dart';

import 'host_ci_test_utils.dart';

/// The version commands faked, the steps run for real by `sh -c [command]`.
class _ShellStepStarter implements HostCiProcessStarter {
  final HostCiFakeProcessStarter fake = fakeStarter();
  final String command;

  _ShellStepStarter(this.command);

  @override
  Future<HostCiProcess> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) {
    if (hostCiStepOfArguments(arguments) != null) {
      return HostCiIoProcessStarter().start('sh', [
        '-c',
        command,
      ], workingDirectory: workingDirectory);
    }
    return fake.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
  }

  @override
  Future<String?> readFlutterVersion() async => null;
}

/// [fakeStarter], the start of the analyze process held until [gate].
class _GatedStarter implements HostCiProcessStarter {
  final HostCiFakeProcessStarter fake = fakeStarter(
    steps: {HostCiStepName.analyze: HostCiFakeProcess.new},
  );
  final gate = Completer<void>();
  final started = Completer<void>();

  @override
  Future<HostCiProcess> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    if (hostCiStepOfArguments(arguments) == HostCiStepName.analyze) {
      started.complete();
      await gate.future;
    }
    return fake.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
  }

  @override
  Future<String?> readFlutterVersion() async => null;
}

void main() {
  late Directory topDir;
  late String repoPath;
  late String ciDir;
  HostCi? hostCi;

  setUp(() async {
    topDir = newTempDir('robustness');
    repoPath = p.join(topDir.path, 'repo');
    ciDir = p.join(topDir.path, 'host_ci');
    await createGitRepo(repoPath, remote: 'git@github.com:owner/repo.git');
  });

  tearDown(() async {
    await hostCi?.close();
    hostCi = null;
    deleteDir(topDir);
  });

  Future<HostCi> open(HostCiProcessStarter starter) async =>
      hostCi = await openTestHostCi(ciDir, starter: starter);

  test(
    'a step printing invalid UTF-8 runs to its end',
    () async {
      // A byte that is not UTF-8 (a Latin-1 file name, a binary dump).
      var hostCi = await open(
        _ShellStepStarter(r"printf 'caf\351\n'; echo done"),
      );
      var project = await hostCi.addProject(repoPath);
      var lines = <HostCiOutputLine>[];
      var run = await hostCi.run(
        project.id,
        trigger: HostCiTrigger.retry,
        only: [HostCiStepName.analyze],
        onLines: lines.addAll,
      );
      expect(run.runStatus, HostCiRunStatus.success, reason: run.error.v);
      expect(lines.map((line) => line.text), containsAll(['caf�', 'done']));
    },
    testOn: '!windows',
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('cancel while reading the run_ci version: cancelled', () async {
    HostCiFakeProcess? runCiVersion;
    var hostCi = await open(
      HostCiFakeProcessStarter(
        onStart: (executable, arguments) {
          if (arguments.first == '--version') {
            return HostCiFakeProcess(
              out: ['Dart SDK version: 3.13.7 (stable)'],
              exitCode: 0,
            );
          }
          if (arguments.contains('--version')) {
            // `dart pub global run dev_build:run_ci --version` takes a
            // second or two: still running when cancelled.
            return runCiVersion = HostCiFakeProcess();
          }
          return HostCiFakeProcess(exitCode: 0);
        },
      ),
    );
    var project = await hostCi.addProject(repoPath);
    var future = hostCi.run(project.id, trigger: HostCiTrigger.manual);
    for (var i = 0; i < 500 && runCiVersion == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    hostCi.cancel();
    var run = await future.timeout(const Duration(seconds: 20));
    expect(run.runStatus, HostCiRunStatus.cancelled, reason: run.error.v);
    expect(runCiVersion!.killCount, 1);
    // Not a failure report ("run_ci not found").
    expect((await hostCi.getProjects())[project.id]!.openFailures, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('cancel while a step process starts: killed', () async {
    var starter = _GatedStarter();
    var hostCi = await open(starter);
    var project = await hostCi.addProject(repoPath);
    var future = hostCi.run(
      project.id,
      trigger: HostCiTrigger.retry,
      only: [HostCiStepName.analyze],
    );
    await starter.started.future.timeout(const Duration(seconds: 20));
    hostCi.cancel();
    starter.gate.complete();
    DbHostCiRun? run;
    try {
      run = await future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Not killed: end it to clean up.
      for (var start in starter.fake.starts) {
        start.process.exit(0);
      }
      await future;
    }
    expect(run?.runStatus, HostCiRunStatus.cancelled);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('two runs asked at once: the second one throws', () async {
    var processes = <HostCiFakeProcess>[];
    var hostCi = await open(
      fakeStarter(
        steps: {
          HostCiStepName.analyze: () {
            var process = HostCiFakeProcess();
            processes.add(process);
            return process;
          },
        },
      ),
    );
    var project = await hostCi.addProject(repoPath);
    Future<DbHostCiRun> run() => hostCi.run(
      project.id,
      trigger: HostCiTrigger.retry,
      only: [HostCiStepName.analyze],
    );
    var first = run();
    var second = run();
    Object? secondError;
    try {
      await second.timeout(const Duration(seconds: 5));
    } catch (e) {
      secondError = e;
    }
    // Whatever happened, end the processes.
    for (var i = 0; i < 100 && processes.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      for (var process in processes) {
        process.exit(0);
      }
    }
    for (var process in processes) {
      process.exit(0);
    }
    await first.timeout(const Duration(seconds: 20));
    expect(secondError, isA<StateError>());
    expect(processes, hasLength(1));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('two waits of one process: one slot at a time', () async {
    HostCiQueueEntry entry(String project) => HostCiQueueEntry(
      pid: pid,
      project: project,
      trigger: 'manual',
      time: DateTime.now(),
    );
    // Two Host CI objects of one process (an app) on the same folder.
    HostCiRunQueue queue() =>
        HostCiRunQueue(ciDir, pollInterval: const Duration(milliseconds: 20));
    var first = queue().acquire(entry('one'));
    var second = queue().acquire(entry('two'));
    var slot1 = await first.timeout(const Duration(seconds: 10));
    HostCiRunSlot? slot2;
    unawaited(second.then((slot) => slot2 = slot));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    var both = slot2 != null;
    await slot1.release();
    await (await second.timeout(const Duration(seconds: 10))).release();
    expect(both, isFalse, reason: 'both slots held at once');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a link never points outside the checkouts folder', () async {
    for (var text in [
      'git@github.com:../..',
      'git@github.com:owner/..',
      'github.com/../..',
      'owner/..',
      'https://github.com/owner/repo/tree/main/..%2F..',
    ]) {
      expect(hostCiParseRepoLink(text), isNull, reason: text);
    }
    var hostCi = await open(fakeStarter());
    var checkouts = await hostCi.getCheckoutsDir();
    // A clone of the same host is there: `<host>/..` resolves.
    Directory(
      p.join(checkouts, 'example.com', 'a'),
    ).createSync(recursive: true);
    var marker = File(p.join(ciDir, 'marker'))..writeAsStringSync('keep');
    await expectLater(
      hostCi.addClone(
        HostCiRepoLink(
          repoId: 'example.com/../..',
          cloneUrl: Uri.file(p.join(topDir.path, 'nope')).toString(),
        ),
      ),
      throwsA(anything),
    );
    expect(marker.existsSync(), isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
