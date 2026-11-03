import 'dart:async';
import 'dart:io';

import 'package:dev_build/package.dart' show recursivePubPath;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_git.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_model.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_process.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_store.dart';

/// One line of output of a run.
class HostCiOutputLine {
  /// The text, without the end of line.
  final String text;

  /// True for a line written on stderr, or reported by the runner itself.
  final bool isError;

  /// Creates a line.
  const HostCiOutputLine(this.text, {this.isError = false});

  @override
  String toString() => text;
}

/// Prefix of the package marker lines of `run_ci`.
const hostCiPackageMarker = '# package: ';

/// Prefix of the command lines echoed by `run_ci`.
const hostCiCommandMarker = r'$ ';

/// The `run_ci` command, run with `dart pub global run`.
const hostCiRunCiPackage = 'dev_build:run_ci';

/// The failing command and package of a `run_ci` error line.
///
/// `run_ci` carries on after a failing package and reports it as
/// `ERROR ShellException(<command>, exitCode <n>, workingDirectory: <dir>) in <dir>`
/// (and once more at the end, `run_ci failed ShellException(...)`). The first
/// such line of a step names the package that failed first, like the GitHub
/// log does; the last `# package:` marker before the exit would name the
/// last package run, not the failing one.
({String command, String package})? hostCiParseRunCiError(String line) {
  var match = RegExp(
    r'ShellException\((.*), exitCode -?\d+, workingDirectory: ([^)]+)\)',
  ).firstMatch(line);
  if (match == null) {
    return null;
  }
  return (command: match.group(1)!.trim(), package: match.group(2)!.trim());
}

/// The first `run_ci` (dev_build) knowing [hostCiNoFatalWarningsArg].
final hostCiRunCiNoFatalWarningsVersion = Version(1, 1, 17, build: '3');

/// True when `run_ci` [version] knows [hostCiNoFatalWarningsArg] (unknown or
/// unreadable: assumed recent).
bool hostCiRunCiHasNoFatalWarnings(String? version) {
  if (version == null) {
    return true;
  }
  try {
    return Version.parse(version) >= hostCiRunCiNoFatalWarningsVersion;
  } catch (_) {
    return true;
  }
}

/// The `dart` arguments of a `run_ci` step of [project] (not
/// [HostCiStepName.buildHost], see [hostCiHostBuildArguments]): `pub global
/// run dev_build:run_ci`, the step arguments, `--recursive` and the project
/// extra arguments. [runCiVersion], when known, drops the arguments an older
/// `run_ci` does not know.
List<String> hostCiStepArguments(
  DbHostCiProject project,
  HostCiStepName step, {
  String? runCiVersion,
}) {
  var noFatalWarnings = hostCiRunCiHasNoFatalWarnings(runCiVersion);
  return [
    'pub',
    'global',
    'run',
    hostCiRunCiPackage,
    for (var arg in step.runCiArguments)
      if (noFatalWarnings || arg != hostCiNoFatalWarningsArg) arg,
    '--recursive',
    ...?project.extraArgs.v,
  ];
}

/// The command of a step of [project] as the reports show it:
/// `dart pub global run dev_build:run_ci ...` ([hostCiStepArguments]),
/// `flutter build <host> --no-pub` for [HostCiStepName.buildHost] (run in
/// each flutter app), the git commands of [HostCiStepName.update].
String hostCiStepCommand(DbHostCiProject project, HostCiStepName step) {
  if (step.isRunCi) {
    return 'dart ${hostCiStepArguments(project, step).join(' ')}';
  }
  if (step == HostCiStepName.update) {
    return project.updateGitCommands
        .map((args) => 'git ${args.join(' ')}')
        .join(' && ');
  }
  var platform = hostCiHostBuildPlatform ?? '<host>';
  return 'flutter ${hostCiHostBuildArguments(platform).join(' ')}';
}

/// The step run by the [arguments] of a step process: the `dart` ones of
/// [hostCiStepArguments], the `flutter` ones of [hostCiHostBuildArguments];
/// null for another command (a fake process starter uses it).
HostCiStepName? hostCiStepOfArguments(List<String> arguments) {
  if (arguments.length == 3 &&
      hostCiHostBuildPlatforms.contains(arguments[1]) &&
      _sameArguments(arguments, hostCiHostBuildArguments(arguments[1]))) {
    return HostCiStepName.buildHost;
  }
  var index = arguments.indexOf(hostCiRunCiPackage);
  if (index < 0) {
    return null;
  }
  var rest = arguments.sublist(index + 1);
  var recursiveIndex = rest.indexOf('--recursive');
  if (recursiveIndex < 0) {
    return null;
  }
  // With or without the arguments dropped for an older run_ci.
  List<String> known(List<String> arguments) =>
      arguments.where((arg) => arg != hostCiNoFatalWarningsArg).toList();
  var stepArguments = known(rest.sublist(0, recursiveIndex));
  for (var step in HostCiStepName.values) {
    if (step.isRunCi &&
        _sameArguments(stepArguments, known(step.runCiArguments))) {
      return step;
    }
  }
  return null;
}

bool _sameArguments(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// The `flutter build` targets of a host build.
const hostCiHostBuildPlatforms = ['linux', 'macos', 'windows'];

/// The `flutter build` target of this host (`linux`, `macos` or `windows`),
/// null on another platform (no host build).
String? get hostCiHostBuildPlatform => Platform.isLinux
    ? 'linux'
    : Platform.isMacOS
    ? 'macos'
    : Platform.isWindows
    ? 'windows'
    : null;

/// The `flutter` arguments of the host build of a flutter app for
/// [platform] (`linux`, `macos` or `windows`).
List<String> hostCiHostBuildArguments(String platform) => [
  'build',
  platform,
  '--no-pub',
];

/// The flutter apps below [root] to build for [platform]: the packages
/// depending on flutter (found like `run_ci` finds them) that have a
/// `<platform>` folder and `lib/main.dart`; their paths relative to [root]
/// with `/` separators on every platform (`flutter_app/example`, `.` for
/// [root] itself), sorted.
Future<List<String>> hostCiHostBuildPackages(
  String root,
  String platform,
) async {
  var apps = <String>[];
  for (var package in await recursivePubPath(
    [root],
    dependencies: ['flutter'],
  )) {
    var dir = p.normalize(p.absolute(root, package));
    if (Directory(p.join(dir, platform)).existsSync() &&
        File(p.join(dir, 'lib', 'main.dart')).existsSync()) {
      var relative = p.relative(dir, from: p.normalize(p.absolute(root)));
      apps.add(p.posix.joinAll(p.split(relative)));
    }
  }
  apps.sort();
  return apps;
}

/// The folders never searched for lock files.
const _lockFilesSkippedDirs = {'build', 'node_modules', 'deploy'};

/// The `pubspec.lock` files below [root] (hidden, build and node_modules
/// folders skipped) with their content, keyed by path.
Future<Map<String, String>> hostCiReadLockFiles(String root) async {
  var files = <String, String>{};
  Future<void> visit(Directory dir) async {
    List<FileSystemEntity> entities;
    try {
      entities = await dir.list(followLinks: false).toList();
    } catch (_) {
      return;
    }
    for (var entity in entities) {
      var name = p.basename(entity.path);
      if (entity is File && name == 'pubspec.lock') {
        try {
          files[entity.path] = await entity.readAsString();
        } catch (_) {}
      } else if (entity is Directory &&
          !name.startsWith('.') &&
          !_lockFilesSkippedDirs.contains(name)) {
        await visit(entity);
      }
    }
  }

  await visit(Directory(root));
  return files;
}

/// Put back the lock files [saved] by [hostCiReadLockFiles] below [root]:
/// the saved ones rewritten, the ones that did not exist then deleted.
Future<void> hostCiRestoreLockFiles(
  String root,
  Map<String, String> saved,
) async {
  var now = await hostCiReadLockFiles(root);
  for (var path in now.keys) {
    if (!saved.containsKey(path)) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }
  for (var entry in saved.entries) {
    if (now[entry.key] != entry.value) {
      await File(entry.key).writeAsString(entry.value, flush: true);
    }
  }
}

/// Runs the CI of one project: the git facts, then one `run_ci` process per
/// step in the repository root (the host build: one `flutter build` per
/// flutter app), the record and the log kept up to date.
///
/// The steps depend on each other: a failing step with the fail policy (the
/// default, always for the pub steps) skips the following ones; a warning or
/// an accepted failure does not. The lock files are saved before the
/// downgrade and put back after it, whatever happens.
///
/// The output goes to [onLines] (buffered, [flushDelay]) and to the log file,
/// every change of the run record to [onRun]. [cancel] kills the current
/// process (and its children), the remaining steps are cancelled.
class HostCiRunner {
  /// The database.
  final HostCiStore store;

  /// Where the log files go.
  final String logsDir;

  /// Starts the processes.
  final HostCiProcessStarter starter;

  /// The project to run.
  final DbHostCiProject project;

  /// What started the run.
  final HostCiTrigger trigger;

  /// Who runs it (`dtk ci`, an app name).
  final String? client;

  /// The steps to run (a retry), [DbHostCiProjectExt.enabledSteps] when null.
  final List<HostCiStepName>? steps;

  /// How partial the run is (with [steps]), null for a full run.
  final HostCiPartial? partial;

  /// The settings at run time.
  final DbHostCiSettings settings;

  /// Called with the new output lines.
  final void Function(List<HostCiOutputLine> lines)? onLines;

  /// Called when the run record changes (same record, updated).
  final void Function(DbHostCiRun run)? onRun;

  /// Called once the run record is added (its key known).
  final Future<void> Function(DbHostCiRun run)? onAdded;

  /// How long output lines are buffered before being reported.
  final Duration flushDelay;

  /// How often the heartbeat is written while running.
  final Duration heartbeatInterval;

  /// How long a cancelled process gets to exit before being killed for good.
  final Duration killTimeout;

  /// The clock, replaced in the tests.
  final DateTime Function() now;

  var _cancelled = false;
  HostCiProcess? _process;
  Timer? _killTimer;
  Timer? _flushTimer;
  Timer? _heartbeatTimer;
  final _pendingLines = <HostCiOutputLine>[];
  IOSink? _logSink;
  DbHostCiRun? _run;
  Future<void>? _running;

  /// Creates a runner, [start] starts it.
  HostCiRunner({
    required this.store,
    required this.logsDir,
    required this.starter,
    required this.project,
    required this.trigger,
    required this.settings,
    this.client,
    this.steps,
    this.partial,
    this.onLines,
    this.onRun,
    this.onAdded,
    this.flushDelay = const Duration(milliseconds: 100),
    this.heartbeatInterval = const Duration(seconds: 10),
    this.killTimeout = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  /// True once [cancel] was called.
  bool get cancelled => _cancelled;

  /// The run record, null before [start].
  DbHostCiRun? get run => _run;

  /// Run the steps, never throws: a failure is in the record.
  ///
  /// Returns the saved run record.
  Future<DbHostCiRun> start() async {
    if (_running != null) {
      throw StateError('already running');
    }
    var completer = Completer<void>();
    _running = completer.future;
    try {
      return await _run_();
    } finally {
      completer.complete();
    }
  }

  Future<DbHostCiRun> _run_() async {
    var startTime = now();
    var steps = this.steps ?? project.enabledSteps;
    var run = _run = DbHostCiRun()
      ..project.v = project.id
      ..path.v = project.path.v
      ..trigger.v = trigger.name
      ..partial.v = partial?.name
      ..client.v = client
      ..pid.v = pid
      ..start.v = startTime.millisecondsSinceEpoch
      ..heartbeat.v = startTime.millisecondsSinceEpoch
      ..status.v = HostCiRunStatus.running.name
      ..steps.v = [
        for (var step in steps)
          () {
            var policy = project.policyOf(step);
            return DbHostCiStep()
              ..name.v = step.name
              ..status.v = HostCiStepStatus.pending.name
              ..policy.v = policy.policy == HostCiFailurePolicy.fail
                  ? null
                  : policy.policy.name
              ..severity.v = policy.policy == HostCiFailurePolicy.warn
                  ? policy.severity.name
                  : null;
          }(),
      ];
    run = _run = await store.addRun(run);
    run.log.v = _logRelativePath(run);
    await onAdded?.call(run);
    _notify();
    try {
      await _openLog(run);
      _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
        run.heartbeat.v = now().millisecondsSinceEpoch;
        unawaited(store.putRun(run).catchError((_) {}));
      });
      await _runSteps(run);
    } catch (e, st) {
      _addLine('$e', isError: true);
      _addLine('$st', isError: true);
      run
        ..status.v = HostCiRunStatus.error.name
        ..error.v = '$e';
    } finally {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      run.end.v = now().millisecondsSinceEpoch;
      _flush();
      await _closeLog();
      await store.putRun(run);
      await _applyRetention(run);
      _notify();
    }
    return run;
  }

  /// Read the git facts of [gitRoot] into [run], with a log line.
  Future<void> _readGitFacts(
    DbHostCiRun run,
    String gitRoot, {
    required bool fetch,
    String what = 'at',
  }) async {
    var git = await hostCiReadGitFacts(gitRoot, fetch: fetch);
    if (git != null) {
      run
        ..head.v = git.head
        ..branch.v = git.branch
        ..commitTime.v = git.commitTime?.millisecondsSinceEpoch
        ..dirty.v = git.dirty
        ..ahead.v = git.ahead
        ..behind.v = git.behind;
      _addLine(
        '# ${project.id} $what ${git.shortHead}'
        '${git.branch == null ? '' : ' (${git.branch})'}'
        '${git.isClean ? ', clean' : ', ${git.dirty} modified file${git.dirty > 1 ? 's' : ''}'}'
        '${git.ahead == null ? '' : ', ${git.ahead} ahead'}',
      );
    }
  }

  Future<void> _runSteps(DbHostCiRun run) async {
    var path = project.path.v ?? '';
    // The git checkout (the clone of a sub folder project).
    var gitRoot = project.gitRoot;
    var stepRecords = run.stepList;

    void fail(String message) {
      _addLine(message, isError: true);
      run
        ..status.v = HostCiRunStatus.error.name
        ..error.v = message;
      for (var step in stepRecords) {
        step.status.v = HostCiStepStatus.skipped.name;
      }
    }

    // The checkout; a clone cleared (or in a temp folder gone) comes back
    // at its update step.
    var updating =
        project.isCloned &&
        stepRecords.any((step) => step.stepName == HostCiStepName.update);
    if (!updating) {
      if (path.isEmpty || !Directory(path).existsSync()) {
        fail(
          'Folder not found: $path'
          '${project.isCloned ? ' (cleared clone: a full run clones it again)' : ''}',
        );
        return;
      }
      if (!hostCiIsGitCheckout(gitRoot)) {
        fail('Not a git checkout: $gitRoot');
        return;
      }
    }
    if (project.isCloned) {
      _addLine(
        '# clone of ${project.cloneUrl.v}'
        '${project.cloneRef.v == null ? '' : ', ${project.cloneRef.v}'}'
        '${project.root.v == null ? '' : ', in ${p.posix.joinAll(p.split(p.relative(path, from: gitRoot)))}'}',
      );
    }
    await _readGitFacts(
      run,
      gitRoot,
      // A clone is fetched by its update step.
      fetch: settings.fetchBeforeRunValue && !project.isCloned,
    );
    var options = project.optionsSummary;
    if (options.isNotEmpty) {
      _addLine('# options: $options');
    }
    await store.putRun(run);
    _notify();
    if (_cancelled) {
      _cancelSteps(run);
      return;
    }

    // The tools.
    var dartVersion = await _readVersion(path, 'dart', ['--version']);
    run.dartVersion.v = dartVersion;
    if (dartVersion == null) {
      fail('dart not found');
      return;
    }
    var runCiVersion = await _readVersion(path, 'dart', [
      'pub',
      'global',
      'run',
      hostCiRunCiPackage,
      '--version',
    ]);
    run.runCiVersion.v = runCiVersion;
    if (runCiVersion == null) {
      fail(
        'run_ci not found, activate it: dart pub global activate dev_build '
        '(or pubglobalupdate)',
      );
      return;
    }
    run.flutterVersion.v = await starter.readFlutterVersion();
    _addLine(
      '# dart $dartVersion'
      '${run.flutterVersion.v == null ? '' : ', flutter ${run.flutterVersion.v}'}'
      ', run_ci $runCiVersion',
    );
    if (!hostCiRunCiHasNoFatalWarnings(runCiVersion) &&
        stepRecords.any(
          (step) => step.stepName == HostCiStepName.analyzeDowngrade,
        )) {
      _addLine(
        '# run_ci $runCiVersion has no $hostCiNoFatalWarningsArg '
        '($hostCiRunCiNoFatalWarningsVersion): the warnings of the analyze '
        'downgrade are fatal, update it: dart pub global activate dev_build',
      );
    }
    await store.putRun(run);
    _notify();

    // The steps, each one depending on the previous ones.
    var blocked = false;
    Map<String, String>? savedLockFiles;
    try {
      for (var index = 0; index < stepRecords.length; index++) {
        var stepRecord = stepRecords[index];
        var step = stepRecord.stepName;
        // The downgrade is always undone once started.
        var restore = step == HostCiStepName.pubRestore;
        if (restore && savedLockFiles != null) {
          var saved = savedLockFiles;
          savedLockFiles = null;
          await hostCiRestoreLockFiles(path, saved);
          _addLine('# ${saved.length} lock files put back');
        }
        if (_cancelled) {
          stepRecord.status.v = HostCiStepStatus.cancelled.name;
          continue;
        }
        if (step == null ||
            (blocked &&
                !(restore &&
                    _statusOf(run, HostCiStepName.pubDowngrade) !=
                        HostCiStepStatus.skipped))) {
          stepRecord.status.v = HostCiStepStatus.skipped.name;
          continue;
        }
        if (step == HostCiStepName.pubDowngrade) {
          savedLockFiles = await hostCiReadLockFiles(path);
        }
        _addLine('=== ${step.label} (${index + 1}/${stepRecords.length}) ===');
        var stepStart = now();
        stepRecord
          ..status.v = HostCiStepStatus.running.name
          ..start.v = stepStart.millisecondsSinceEpoch;
        await store.putRun(run);
        _notify();
        var exitCode = step.isRunCi
            ? await _runStepProcess(
                path,
                'dart',
                hostCiStepArguments(project, step, runCiVersion: runCiVersion),
                stepRecord,
              )
            : step == HostCiStepName.update
            ? await _runUpdate(gitRoot, stepRecord)
            : await _runHostBuild(path, stepRecord);
        if (step == HostCiStepName.update && exitCode == 0) {
          // The run is about the updated commit.
          await _readGitFacts(run, gitRoot, fetch: false, what: 'updated to');
          if (!Directory(path).existsSync()) {
            _addLine('Folder not found after the update: $path', isError: true);
            exitCode = 1;
          }
        }
        stepRecord
          ..exitCode.v = exitCode
          ..duration.v = now().difference(stepStart).inMilliseconds;
        if (_cancelled) {
          stepRecord.status.v = HostCiStepStatus.cancelled.name;
        } else if (exitCode == 0) {
          stepRecord.status.v = HostCiStepStatus.success.name;
          stepRecord.failedPackage.clear();
          stepRecord.failedCommand.clear();
        } else {
          stepRecord.status.v = HostCiStepStatus.failure.name;
          if (stepRecord.isBlockingFailure) {
            blocked = true;
          }
          _addLine(
            '${step.label} failed (exit code $exitCode)'
            '${stepRecord.failedPackage.v == null ? '' : ' in ${stepRecord.failedPackage.v}'}'
            '${stepRecord.isWarning ? ', warning (${stepRecord.severityValue.name})' : ''}'
            '${stepRecord.isAcceptedFailure ? ', accepted' : ''}',
            isError: true,
          );
        }
        await store.putRun(run);
        _notify();
      }
    } finally {
      // Cancelled or thrown during the downgrade: the lock files anyway.
      if (savedLockFiles != null) {
        await hostCiRestoreLockFiles(path, savedLockFiles);
        _addLine('# ${savedLockFiles.length} lock files put back');
      }
    }
    if (_cancelled) {
      _cancelSteps(run);
      return;
    }
    run.status.v = hostCiRunStatusOfSteps(stepRecords).name;
    _addLine(
      '=== ${run.runStatus.name}, ${hostCiFormatDuration(now().difference(run.startDateTime!))} ===',
    );
  }

  HostCiStepStatus? _statusOf(DbHostCiRun run, HostCiStepName name) {
    for (var step in run.stepList) {
      if (step.stepName == name) {
        return step.stepStatus;
      }
    }
    return null;
  }

  void _cancelSteps(DbHostCiRun run) {
    run.status.v = HostCiRunStatus.cancelled.name;
    for (var step in run.stepList) {
      if (step.stepStatus == HostCiStepStatus.pending ||
          step.stepStatus == HostCiStepStatus.running) {
        step.status.v = HostCiStepStatus.cancelled.name;
      }
    }
    _addLine('=== cancelled ===', isError: true);
  }

  /// Run one step process, the output to the log and the console, the hints
  /// to [stepRecord]; the exit code (null when it could not start).
  Future<int?> _runStepProcess(
    String path,
    String executable,
    List<String> arguments,
    DbHostCiStep stepRecord,
  ) async {
    _addLine('$hostCiCommandMarker$executable ${arguments.join(' ')}');
    HostCiProcess process;
    try {
      process = await starter.start(
        executable,
        arguments,
        workingDirectory: path,
      );
    } catch (e) {
      _addLine('$e', isError: true);
      return null;
    }
    _process = process;
    try {
      // The package and command running now (the live caption), and the
      // first failure reported by run_ci.
      ({String command, String package})? error;
      void onLine(String line, {bool isError = false}) {
        if (line.startsWith(hostCiPackageMarker)) {
          stepRecord.failedPackage.v = line
              .substring(hostCiPackageMarker.length)
              .trim();
          stepRecord.failedCommand.clear();
          _notify();
        } else if (line.startsWith(hostCiCommandMarker)) {
          stepRecord.failedCommand.v = line
              .substring(hostCiCommandMarker.length)
              .trim();
          _notify();
        } else {
          error ??= hostCiParseRunCiError(line);
        }
        _addLine(line, isError: isError);
      }

      var outDone = process.stdoutLines.listen(onLine).asFuture<void>();
      var errDone = process.stderrLines
          .listen((line) => onLine(line, isError: true))
          .asFuture<void>();
      var exitCode = await process.exitCode;
      await _awaitOutput(outDone, errDone);
      if (exitCode != 0 && error != null) {
        // The first failing package, not the last one run.
        stepRecord
          ..failedPackage.v = error!.package
          ..failedCommand.v = error!.command;
      }
      return exitCode;
    } finally {
      _process = null;
      _killTimer?.cancel();
      _killTimer = null;
    }
  }

  /// The update of a cloned checkout in [gitRoot]: its git commands
  /// ([DbHostCiProjectExt.updateGitCommands]) one after the other, stopping at
  /// the first failure.
  ///
  /// Returns the exit code of the failing command (null when it could not
  /// start), 0 when all succeed.
  Future<int?> _runUpdate(String gitRoot, DbHostCiStep stepRecord) async {
    if (!hostCiIsGitCheckout(gitRoot)) {
      // Cleared (or a temp folder gone): cloned again.
      var dir = Directory(gitRoot);
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
      await dir.parent.create(recursive: true);
      var arguments = hostCiCloneArguments(
        project.cloneUrl.v!,
        gitRoot,
        ref: project.cloneRef.v,
      );
      var command = 'git ${arguments.join(' ')}';
      stepRecord
        ..failedPackage.v = '.'
        ..failedCommand.v = command;
      _notify();
      var exitCode = await _runStepProcess(
        dir.parent.path,
        'git',
        arguments,
        stepRecord,
      );
      if (exitCode != 0) {
        stepRecord
          ..failedPackage.v = '.'
          ..failedCommand.v = command;
      }
      return exitCode;
    }
    for (var arguments in project.updateGitCommands) {
      if (_cancelled) {
        return null;
      }
      var command = 'git ${arguments.join(' ')}';
      stepRecord
        ..failedPackage.v = '.'
        ..failedCommand.v = command;
      _notify();
      var exitCode = await _runStepProcess(
        gitRoot,
        'git',
        arguments,
        stepRecord,
      );
      if (exitCode != 0) {
        stepRecord
          ..failedPackage.v = '.'
          ..failedCommand.v = command;
        return exitCode;
      }
    }
    return 0;
  }

  /// The host build: `flutter build <host> --no-pub` in each flutter app
  /// ([hostCiHostBuildPackages]), all of them even after a failure (like
  /// `run_ci` with its packages), the first failure kept in [stepRecord].
  ///
  /// Returns the exit code of the first failure (null when it could not
  /// start), 0 when all succeed or there is nothing to build.
  Future<int?> _runHostBuild(String root, DbHostCiStep stepRecord) async {
    var platform = hostCiHostBuildPlatform;
    if (platform == null) {
      _addLine('# no host build on ${Platform.operatingSystem}');
      return 0;
    }
    var packages = await hostCiHostBuildPackages(root, platform);
    if (packages.isEmpty) {
      _addLine('# no flutter app with $platform/ and lib/main.dart');
      return 0;
    }
    var arguments = hostCiHostBuildArguments(platform);
    var command = 'flutter ${arguments.join(' ')}';
    ({int? exitCode, String package})? failure;
    for (var package in packages) {
      if (_cancelled) {
        break;
      }
      _addLine('$hostCiPackageMarker$package');
      stepRecord
        ..failedPackage.v = package
        ..failedCommand.v = command;
      _notify();
      var exitCode = await _runStepProcess(
        p.normalize(p.join(root, package)),
        'flutter',
        arguments,
        stepRecord,
      );
      if (exitCode != 0) {
        failure ??= (exitCode: exitCode, package: package);
      }
    }
    if (failure != null) {
      stepRecord
        ..failedPackage.v = failure.package
        ..failedCommand.v = command;
      return failure.exitCode;
    }
    return 0;
  }

  /// The version printed by `executable arguments`, the first line holding a
  /// digit (`Dart SDK version: 3.13.7 (stable) ...` gives `3.13.7`), null
  /// when the command fails.
  Future<String?> _readVersion(
    String path,
    String executable,
    List<String> arguments,
  ) async {
    try {
      var process = await starter.start(
        executable,
        arguments,
        workingDirectory: path,
      );
      _process = process;
      var out = <String>[];
      var outDone = process.stdoutLines.listen(out.add).asFuture<void>();
      var errDone = process.stderrLines.listen(out.add).asFuture<void>();
      var exitCode = await process.exitCode;
      await _awaitOutput(outDone, errDone);
      _process = null;
      if (exitCode != 0) {
        for (var line in out) {
          _addLine(line, isError: true);
        }
        return null;
      }
      for (var line in out) {
        var match = RegExp(r'\d+\.\d+[\w.+-]*').firstMatch(line);
        if (match != null) {
          return match.group(0);
        }
      }
      return out.isEmpty ? '?' : out.first.trim();
    } catch (e) {
      _process = null;
      _addLine('$e', isError: true);
      return null;
    }
  }

  /// The output ends with the process: wait for the streams, 2 s at most
  /// (a timer cancelled on the way, nothing left pending).
  Future<void> _awaitOutput(Future<void> outDone, Future<void> errDone) async {
    var timeout = Completer<void>();
    var timer = Timer(const Duration(seconds: 2), timeout.complete);
    try {
      await Future.any([
        Future.wait([outDone, errDone]),
        timeout.future,
      ]);
    } finally {
      timer.cancel();
    }
  }

  /// Kill the running process, the remaining steps are cancelled.
  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    var process = _process;
    if (process != null) {
      process.kill();
      // Still there after a while: no mercy.
      _killTimer = Timer(killTimeout, () {
        if (_process == process) {
          process.kill(force: true);
        }
      });
    }
  }

  /// `<id segments>/<key>.log`, the id segments made file name safe.
  String _logRelativePath(DbHostCiRun run) {
    var segments = project.id
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map((segment) => segment.replaceAll(RegExp(r'[^\w.-]'), '_'))
        .toList();
    return p.joinAll([...segments, '${run.id}.log']);
  }

  Future<void> _openLog(DbHostCiRun run) async {
    var file = File(p.join(logsDir, run.log.v!));
    await file.parent.create(recursive: true);
    _logSink = file.openWrite();
    _logSink!.writeln(
      '# host ci run ${run.id}, ${project.id}, ${project.path.v}, '
      '${run.startDateTime!.toIso8601String()}, trigger ${trigger.name}'
      '${client == null ? '' : ', $client'}',
    );
  }

  Future<void> _closeLog() async {
    var sink = _logSink;
    _logSink = null;
    if (sink != null) {
      try {
        await sink.flush();
        await sink.close();
      } catch (_) {
        // The disk is full, the folder is gone: the record is what matters.
      }
    }
  }

  Future<void> _applyRetention(DbHostCiRun run) async {
    try {
      var removed = await store.applyLogRetention(
        project.id,
        logsKept: settings.logsKeptValue,
      );
      for (var relativePath in removed) {
        var file = File(p.join(logsDir, relativePath));
        if (file.existsSync()) {
          await file.delete();
        }
      }
    } catch (_) {
      // Best effort.
    }
  }

  void _notify() {
    var run = _run;
    if (run != null) {
      onRun?.call(run);
    }
  }

  void _addLine(String text, {bool isError = false}) {
    _logSink?.writeln(isError ? '! $text' : text);
    if (onLines == null) {
      return;
    }
    _pendingLines.add(HostCiOutputLine(text, isError: isError));
    _flushTimer ??= Timer(flushDelay, _flush);
  }

  void _flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pendingLines.isEmpty) {
      return;
    }
    var lines = List<HostCiOutputLine>.from(_pendingLines);
    _pendingLines.clear();
    onLines?.call(lines);
  }
}

/// The status of a run from its [steps]: failure when a step failed with
/// the fail policy, warning when only warnings, success otherwise.
HostCiRunStatus hostCiRunStatusOfSteps(List<DbHostCiStep> steps) {
  if (steps.any((step) => step.isBlockingFailure)) {
    return HostCiRunStatus.failure;
  }
  if (steps.any((step) => step.isWarning)) {
    return HostCiRunStatus.warning;
  }
  return HostCiRunStatus.success;
}

/// Read the log of [run] from [logsDir], empty when the file is gone.
///
/// The runner prefixes the stderr lines with `! `, they are flagged back.
Future<List<HostCiOutputLine>> hostCiReadLog(
  String logsDir,
  DbHostCiRun run,
) async {
  var relativePath = run.log.v;
  if (relativePath == null) {
    return const [];
  }
  var file = File(p.join(logsDir, relativePath));
  if (!file.existsSync()) {
    return const [];
  }
  var lines = await file.readAsLines();
  return lines.map((line) {
    if (line.startsWith('! ')) {
      return HostCiOutputLine(line.substring(2), isError: true);
    }
    return HostCiOutputLine(line);
  }).toList();
}

/// The step header lines of a log: `=== <label> (n/N) ===`.
final _hostCiStepHeader = RegExp(r'^=== (.+) \((\d+)/(\d+)\) ===$');

/// A section of a log: the lines of one step, or the lines before the first
/// step (the git facts, the tool versions) when [step] is null.
class HostCiLogSection {
  /// The step, null for the lines before the first step.
  final HostCiStepName? step;

  /// The step label, `run` before the first step.
  final String title;

  /// The lines, the header included.
  final List<HostCiOutputLine> lines;

  /// Creates a section.
  HostCiLogSection({
    required this.step,
    required this.title,
    required this.lines,
  });

  @override
  String toString() => '$title (${lines.length})';
}

/// Split the lines of a log by step, in order (the empty sections dropped).
List<HostCiLogSection> hostCiLogSections(List<HostCiOutputLine> lines) {
  var sections = <HostCiLogSection>[];
  var current = HostCiLogSection(step: null, title: 'run', lines: []);
  sections.add(current);
  for (var line in lines) {
    var match = _hostCiStepHeader.firstMatch(line.text);
    if (match != null) {
      var label = match.group(1)!;
      HostCiStepName? step;
      for (var value in HostCiStepName.values) {
        if (value.label == label) {
          step = value;
        }
      }
      current = HostCiLogSection(step: step, title: label, lines: []);
      sections.add(current);
    }
    current.lines.add(line);
  }
  return sections.where((section) => section.lines.isNotEmpty).toList();
}
