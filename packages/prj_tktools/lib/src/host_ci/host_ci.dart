import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:process_run/shell.dart' show userAppDataPath;
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart'
    show sdbFactoryIo, SdbFactorySandboxExtension;
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_git.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_lock.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_model.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_next.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_process.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_report.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_runner.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_store.dart';

/// Environment variable overriding the Host CI folder.
const hostCiDirEnvKey = 'TEKARTIK_HOST_CI_DIR';

/// The Host CI folder of this machine: `$TEKARTIK_HOST_CI_DIR`, else
/// `~/.config/tekartik/host_ci` (`%APPDATA%\tekartik\host_ci` on Windows).
String get hostCiDefaultDir =>
    Platform.environment[hostCiDirEnvKey] ??
    p.join(userAppDataPath, 'tekartik', 'host_ci');

/// The steps of a re-run of [project] from [from]: [from] (the first of the
/// downgrade steps for one of them) and the enabled steps after it.
List<HostCiStepName> hostCiStepsFrom(
  DbHostCiProject project,
  HostCiStepName from,
) {
  if (from.isDowngrade) {
    from = HostCiStepName.pubDowngrade;
  }
  return hostCiNormalizeSteps([
    from,
    for (var step in project.enabledSteps)
      if (step.index > from.index) step,
  ]);
}

/// Host CI: the CI of local checkouts run on this machine.
///
/// Everything is in [dir], local to the machine: the database (projects, runs,
/// settings), the logs, the run queue. Several processes share it (the
/// `dtk ci` command line, an app): the database is opened for each access,
/// one run at a time on the machine, the oldest asked first ([queue]).
class HostCi {
  /// Logs folder name in [dir].
  static const logsDirName = 'logs';

  /// The Host CI folder.
  final String dir;

  /// The database.
  final HostCiStore store;

  /// Where the log files are.
  final String logsDir;

  /// One run at a time on the machine.
  final HostCiRunQueue queue;

  /// Starts the processes (a fake in the tests).
  final HostCiProcessStarter starter;

  /// The clock, replaced in the tests.
  final DateTime Function() now;

  /// Who runs (`dtk ci`, an app name), recorded in the runs.
  final String? client;

  /// Whether the web report ([report]) is written along the runs.
  final bool writeReport;

  /// The web report, in `<dir>/report`.
  late final report = HostCiReport(this);

  /// The report writes, one after the other.
  Future<void> _reportWrite = Future<void>.value();

  final _changeController = StreamController<void>.broadcast();
  HostCiRunner? _runner;
  Completer<void>? _waitCancel;
  Timer? _watchTimer;
  String? _watchSignature;

  /// Creates Host CI in [dir], nothing is opened ([open] also recovers the
  /// interrupted runs).
  HostCi({
    required this.dir,
    required this.store,
    HostCiRunQueue? queue,
    HostCiProcessStarter? starter,
    DateTime Function()? now,
    this.client,
    this.writeReport = true,
  }) : logsDir = p.join(dir, logsDirName),
       queue = queue ?? HostCiRunQueue(dir),
       starter = starter ?? HostCiIoProcessStarter(),
       now = now ?? DateTime.now;

  /// Host CI in [dir] ([hostCiDefaultDir] by default), its database through
  /// [factory] (the io one in [dir] by default) with [lock] (a file lock in
  /// [dir] by default, [HostCiMemoryLock] for a memory database); the runs
  /// left running by a dead process become errors.
  static Future<HostCi> open({
    String? dir,
    SdbFactory? factory,
    HostCiLock? lock,
    HostCiProcessStarter? starter,
    DateTime Function()? now,
    String? client,
    Duration? pollInterval,
    bool writeReport = true,
  }) async {
    dir ??= hostCiDefaultDir;
    await Directory(dir).create(recursive: true);
    var store = HostCiStore(
      factory ?? sdbFactoryIo.sandbox(path: dir),
      lock:
          lock ??
          HostCiFileLock(p.join(dir, '${HostCiStore.defaultDbName}.lock')),
    );
    var hostCi = HostCi(
      dir: dir,
      store: store,
      queue: pollInterval == null
          ? null
          : HostCiRunQueue(dir, pollInterval: pollInterval),
      starter: starter,
      now: now,
      client: client,
      writeReport: writeReport,
    );
    await hostCi.recoverInterruptedRuns();
    return hostCi;
  }

  /// The database file (with the io factory).
  String get dbPath => p.join(dir, HostCiStore.defaultDbName);

  /// Every time the projects, the runs, the settings or the queue change,
  /// in this process or (once [startWatching]) in another one.
  Stream<void> get onChanged => _changeController.stream;

  /// True while this process runs (or waits to run) a project.
  bool get isBusy => _runner != null || _waitCancel != null;

  /// True while this process runs a project.
  bool get isRunning => _runner != null;

  /// The runner of the run in progress in this process, null when none.
  HostCiRunner? get runner => _runner;

  void _changed() {
    if (!_changeController.isClosed) {
      _changeController.add(null);
    }
  }

  /// Watch the database and the queue for the changes of the other
  /// processes, checked every [interval] ([onChanged] fires).
  void startWatching({Duration interval = const Duration(seconds: 1)}) {
    _watchTimer?.cancel();
    _watchSignature = _readWatchSignature();
    _watchTimer = Timer.periodic(interval, (_) {
      var signature = _readWatchSignature();
      if (signature != _watchSignature) {
        _watchSignature = signature;
        _changed();
      }
    });
  }

  /// Stop watching.
  void stopWatching() {
    _watchTimer?.cancel();
    _watchTimer = null;
  }

  String _readWatchSignature() {
    String stat(String path) {
      try {
        var stat = File(path).statSync();
        return stat.type == FileSystemEntityType.notFound
            ? '-'
            : '${stat.modified.microsecondsSinceEpoch}:${stat.size}';
      } catch (_) {
        return '-';
      }
    }

    String list(String path) {
      try {
        var dir = Directory(path);
        if (!dir.existsSync()) {
          return '-';
        }
        var names =
            dir
                .listSync(followLinks: false)
                .map((entity) => p.basename(entity.path))
                .toList()
              ..sort();
        return names.join(',');
      } catch (_) {
        return '-';
      }
    }

    return [
      stat(dbPath),
      stat(queue.runningPath),
      list(queue.queueDir),
    ].join('|');
  }

  /// The runs left running by a process that is gone become errors.
  Future<List<DbHostCiRun>> recoverInterruptedRuns() async {
    int? livePid;
    if (_runner != null) {
      livePid = pid;
    } else {
      livePid = (await queue.readRunning())?.pid;
    }
    var interrupted = await store.recoverInterruptedRuns(
      livePid: livePid,
      now: now(),
    );
    if (interrupted.isNotEmpty) {
      _changed();
    }
    return interrupted;
  }

  /// The git facts read last, per checkout path, with the commits since
  /// the head they were counted from.
  final _gitCache =
      <String, ({HostCiGitFacts? git, String? lastHead, int? commitsSince})>{};

  /// The projects with their last run, their open failure reports, their
  /// git facts and their bucket, ordered (the due ones first).
  ///
  /// With [cachedGit], the git facts read by an earlier call are reused (a
  /// few git commands per project otherwise): the report pages written
  /// during a run use it.
  Future<HostCiProjects> getProjects({bool cachedGit = false}) async {
    await recoverInterruptedRuns();
    var snapshot = await store.getSnapshot();
    var settings = snapshot.settings;
    var current = now();
    var statuses = await Future.wait(
      snapshot.projects.map((project) async {
        var path = project.path.v ?? '';
        var runs = snapshot.runsOf(project.id);
        var lastRun = runs.lastOrNull;
        var lastCompleted = hostCiLastCompletedRun(runs);
        var lastHead = lastCompleted?.head.v;
        HostCiGitFacts? git;
        int? commitsSince;
        var cached = cachedGit ? _gitCache[path] : null;
        if (cached != null && cached.lastHead == lastHead) {
          git = cached.git;
          commitsSince = cached.commitsSince;
        } else {
          git = path.isEmpty ? null : await hostCiReadGitFacts(path);
          if (git != null && lastHead != null && lastHead != git.head) {
            commitsSince = await hostCiCountCommits(path, lastHead, git.head);
          }
          _gitCache[path] = (
            git: git,
            lastHead: lastHead,
            commitsSince: commitsSince,
          );
        }
        var (bucket, reason) = hostCiBucketOf(
          project: project,
          lastCompletedRun: lastCompleted,
          git: git,
          commitsSince: commitsSince,
          staleAfter: settings.staleAfter,
          now: current,
        );
        if (git == null && !project.isPaused) {
          reason = 'folder not found';
        }
        return HostCiProjectStatus(
          project: project,
          lastRun: lastRun,
          lastCompletedRun: lastCompleted,
          openFailures: hostCiOpenFailureRuns(runs),
          git: git,
          commitsSince: commitsSince,
          bucket: bucket,
          reason: reason,
        );
      }),
    );
    return HostCiProjects(hostCiSortStatuses(statuses));
  }

  /// The project matching [query] (id, `owner/repo`, name), null when none
  /// or ambiguous.
  Future<DbHostCiProject?> findProject(String query) async =>
      hostCiFindProject(await store.getProjects(), query);

  /// The most recent run of any project, null when none.
  Future<DbHostCiRun?> getLatestRun() => store.getLatestRun();

  /// The last run of a project, null when never run.
  Future<DbHostCiRun?> getLastRun(String projectId) =>
      store.getLastRun(projectId);

  /// The runs of a project, the oldest first.
  Future<List<DbHostCiRun>> getRuns(String projectId) =>
      store.getRuns(projectId);

  /// One run, null when unknown.
  Future<DbHostCiRun?> getRun(int runId) => store.getRun(runId);

  /// The run in progress and the waiting ones on this machine.
  Future<HostCiQueueState> getQueue() => queue.readState();

  /// Add the checkout at [path], its id is the unique name of its remote
  /// ([id] when given), its name the folder name ([name] when given).
  ///
  /// Returns the existing project when it is already there.
  Future<DbHostCiProject> addProject(
    String path, {
    String? id,
    String? name,
  }) async {
    var canonicalPath = hostCiCanonicalPath(path);
    id ??= await hostCiProjectIdForPath(canonicalPath);
    var project = await store.addProject(
      id: id,
      path: canonicalPath,
      name: name ?? p.basename(canonicalPath),
      now: now(),
    );
    _changed();
    return project;
  }

  /// Remove a project and its runs, the log files stay until
  /// [purgeDeletedProject] (so that [restoreProject] brings everything back).
  Future<HostCiDeletedProject?> removeProject(String id) async {
    var deleted = await store.deleteProject(id);
    _changed();
    return deleted;
  }

  /// Put a removed project back, with its runs.
  Future<void> restoreProject(HostCiDeletedProject deleted) async {
    await store.restoreProject(deleted);
    _changed();
  }

  /// Delete the log files of a removed project.
  Future<void> purgeDeletedProject(HostCiDeletedProject deleted) async {
    for (var relativePath in deleted.logPaths) {
      try {
        var file = File(p.join(logsDir, relativePath));
        if (file.existsSync()) {
          await file.delete();
        }
      } catch (_) {
        // Best effort.
      }
    }
  }

  Future<DbHostCiProject> _updateProject(
    String id,
    void Function(DbHostCiProject project) update,
  ) async {
    var project = await store.updateProject(id, update);
    if (project == null) {
      throw StateError('Unknown project $id');
    }
    _changed();
    return project;
  }

  /// Skip (or not) a project: never proposed, never run by "next" or "all
  /// due".
  Future<void> setPaused(String id, {required bool paused}) =>
      _updateProject(id, (project) {
        if (paused) {
          project.paused.v = true;
        } else {
          project.paused.clear();
        }
      });

  /// Skip (or not) a test platform of a project.
  Future<DbHostCiProject> setPlatformSkipped(
    String id,
    HostCiPlatform platform, {
    required bool skipped,
  }) => _updateProject(id, (project) {
    var platforms = project.skippedPlatforms.toSet();
    if (skipped) {
      platforms.add(platform);
    } else {
      platforms.remove(platform);
    }
    if (platforms.isEmpty) {
      project.skipPlatforms.clear();
    } else {
      project.skipPlatforms.v = [
        for (var value in HostCiPlatform.values)
          if (platforms.contains(value)) value.name,
      ];
    }
  });

  /// Set what a failure of [step] does to the runs of a project.
  Future<DbHostCiProject> setStepPolicy(
    String id,
    HostCiStepName step,
    HostCiFailurePolicy policy, {
    HostCiSeverity? severity,
  }) => _updateProject(
    id,
    (project) => project.setPolicy(step, policy, severity: severity),
  );

  /// Set the options of a project: the enabled [steps] among
  /// [hostCiSelectableSteps] (null for all), `pub get` instead of `pub
  /// upgrade` ([pubGetOnly]) and the [extraArgs] (null for none); a null
  /// [pubGetOnly] leaves it as it is.
  Future<void> setProjectOptions(
    String id, {
    required List<HostCiStepName>? steps,
    required List<String>? extraArgs,
    bool? pubGetOnly,
  }) => _updateProject(id, (project) {
    if (steps == null || steps.toSet().containsAll(hostCiSelectableSteps)) {
      project.steps.clear();
    } else {
      project.steps.v = [
        for (var step in hostCiSelectableSteps)
          if (steps.contains(step)) step.name,
      ];
    }
    if (extraArgs == null || extraArgs.isEmpty) {
      project.extraArgs.clear();
    } else {
      project.extraArgs.v = extraArgs;
    }
    if (pubGetOnly != null) {
      if (pubGetOnly) {
        project.pubGetOnly.v = true;
      } else {
        project.pubGetOnly.clear();
      }
    }
  });

  /// Validate the open failure reports of a project (only [runId] when
  /// given): read and accepted, they are no longer kept open; returns them.
  Future<List<DbHostCiRun>> validate(String projectId, {int? runId}) async {
    var runs = await store.validate(projectId, runId: runId, now: now());
    if (runs.isNotEmpty) {
      _changed();
      for (var run in runs) {
        _scheduleReport(run, index: run == runs.last);
      }
      await _reportWrite;
    }
    return runs;
  }

  /// The settings.
  Future<DbHostCiSettings> getSettings() => store.getSettings();

  /// Write the settings.
  Future<void> setSettings(DbHostCiSettings settings) async {
    await store.setSettings(settings);
    _changed();
  }

  /// The repositories hidden from the candidates.
  Future<Set<String>> getHiddenRepos() async =>
      (await store.getSettings()).hiddenRepoSet;

  /// Hide (or show again) a repository in the candidates.
  Future<void> setRepoHidden(String id, {required bool hidden}) async {
    await store.updateSettings((settings) {
      var hiddenRepos = settings.hiddenRepoSet;
      if (hidden) {
        hiddenRepos.add(id);
      } else {
        hiddenRepos.remove(id);
      }
      if (hiddenRepos.isEmpty) {
        settings.hiddenRepos.clear();
      } else {
        settings.hiddenRepos.v = hiddenRepos.toList()..sort();
      }
    });
    _changed();
  }

  /// The log of a run, empty when its file is gone.
  Future<List<HostCiOutputLine>> readLog(DbHostCiRun run) =>
      hostCiReadLog(logsDir, run);

  /// Run the project [projectId], after the runs asked before on this
  /// machine (the oldest asked first).
  ///
  /// A retry runs some steps only: [only] these ones (never a verdict), or
  /// [from] this one to the end of the enabled steps (a green one closes the
  /// reports when it starts at the failed step or before), on the checkout as
  /// it is; a downgrade step brings the three of them.
  ///
  /// Throws a [StateError] when this process already runs (or waits) or the
  /// project is unknown, a [HostCiQueueCancelledException] when [cancel] is
  /// called while waiting. The queue goes to [onWaiting] while waiting, the
  /// output to [onLines], the record changes to [onRun]. Returns the saved
  /// run record.
  Future<DbHostCiRun> run(
    String projectId, {
    required HostCiTrigger trigger,
    void Function(HostCiQueueState state)? onWaiting,
    void Function(List<HostCiOutputLine> lines)? onLines,
    void Function(DbHostCiRun run)? onRun,
    List<HostCiStepName>? only,
    HostCiStepName? from,
  }) async {
    if (only != null && from != null) {
      throw ArgumentError('only or from, not both');
    }
    if (isBusy) {
      throw StateError(
        'A run is in progress (${_runner?.project.id ?? 'waiting'})',
      );
    }
    var project = await store.getProject(projectId);
    if (project == null) {
      throw StateError('Unknown project $projectId');
    }
    String? stepsSignature;
    var waitCancel = _waitCancel = Completer<void>();
    HostCiRunSlot slot;
    try {
      slot = await queue.acquire(
        HostCiQueueEntry(
          pid: pid,
          project: projectId,
          trigger: trigger.name,
          client: client,
          time: now(),
        ),
        onWaiting: onWaiting,
        cancel: waitCancel.future,
      );
    } finally {
      _waitCancel = null;
    }
    try {
      // Read again: it may have changed while waiting.
      project = await store.getProject(projectId) ?? project;
      var settings = await store.getSettings();
      var steps = only != null
          ? hostCiNormalizeSteps(only)
          : from != null
          ? hostCiStepsFrom(project, from)
          : null;
      var runner = _runner = HostCiRunner(
        store: store,
        logsDir: logsDir,
        starter: starter,
        project: project,
        trigger: trigger,
        settings: settings,
        client: client,
        steps: steps,
        partial: only != null
            ? HostCiPartial.only
            : from != null
            ? HostCiPartial.from
            : null,
        onLines: onLines,
        onRun: (run) {
          onRun?.call(run);
          // The pages follow the steps.
          var signature = run.stepList.map((step) => step.status.v).join();
          if (signature != stepsSignature) {
            stepsSignature = signature;
            _scheduleReport(run, index: true);
          }
        },
        onAdded: (run) async {
          await slot.setRunId(run.id);
          _changed();
        },
        now: now,
      );
      _changed();
      var run = await runner.start();
      _runner = null;
      await slot.release();
      _scheduleReport(run, index: true, project: true);
      await _reportWrite;
      return run;
    } finally {
      _runner = null;
      await slot.release();
      _changed();
    }
  }

  /// Write the pages of [run] (and the index, its project) after the
  /// writes in progress; a failure is ignored (the report is a view).
  void _scheduleReport(
    DbHostCiRun run, {
    bool index = false,
    bool project = false,
  }) {
    if (!writeReport) {
      return;
    }
    var copy = run.scvClone();
    _reportWrite = _reportWrite.then((_) async {
      try {
        if (project) {
          await report.writeForRun(copy);
        } else {
          await report.writeRun(copy);
          if (index) {
            await report.writeIndex();
          }
        }
      } catch (_) {}
    });
  }

  /// Cancel the run in progress (or the wait) of this process, nothing when
  /// none.
  void cancel() {
    var waitCancel = _waitCancel;
    if (waitCancel != null && !waitCancel.isCompleted) {
      waitCancel.complete();
    }
    _runner?.cancel();
  }

  /// Stop watching, a run in progress is cancelled.
  Future<void> close() async {
    stopWatching();
    cancel();
    await _changeController.close();
  }
}
