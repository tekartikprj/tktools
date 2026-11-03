import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_lock.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_model.dart';

/// Everything a status needs, read in one session.
class HostCiSnapshot {
  /// The projects, in the order added.
  final List<DbHostCiProject> projects;

  /// The runs per project id, the oldest first.
  final Map<String, List<DbHostCiRun>> runs;

  /// The settings.
  final DbHostCiSettings settings;

  /// Creates a snapshot.
  HostCiSnapshot({
    required this.projects,
    required this.runs,
    required this.settings,
  });

  /// The runs of a project, the oldest first.
  List<DbHostCiRun> runsOf(String projectId) => runs[projectId] ?? const [];
}

/// The Host CI database: the projects, their runs and the settings.
///
/// Several processes use it (the command line, an app): every access is a
/// short session (open, act, close) holding [lock], nothing stays open.
class HostCiStore {
  /// Default database name.
  static const defaultDbName = 'host_ci.db';

  /// The sdb factory.
  final SdbFactory factory;

  /// The database name in [factory].
  final String dbName;

  /// The lock held during a session.
  final HostCiLock lock;

  /// Creates the store, nothing is opened.
  HostCiStore(this.factory, {this.dbName = defaultDbName, required this.lock}) {
    initCvHostCi();
  }

  /// Run [action] on the open database, holding the lock.
  ///
  /// Never call another method of the store from [action] (no nested
  /// sessions).
  Future<T> session<T>(Future<T> Function(SdbDatabase db) action) =>
      lock.synchronized(() async {
        var db = await factory.openDatabase(
          dbName,
          options: SdbOpenDatabaseOptions(
            version: hostCiDbVersion,
            schema: hostCiSchema,
          ),
        );
        try {
          return await action(db);
        } finally {
          await db.close();
        }
      });

  /// The projects, the runs and the settings, in one session.
  Future<HostCiSnapshot> getSnapshot() => session((db) async {
    var projects = await _getProjects(db);
    var runs = await hostCiRunStore.findRecords(db);
    runs.sort((a, b) => a.id.compareTo(b.id));
    var byProject = <String, List<DbHostCiRun>>{};
    for (var run in runs) {
      var projectId = run.project.v;
      if (projectId != null) {
        (byProject[projectId] ??= []).add(run);
      }
    }
    return HostCiSnapshot(
      projects: projects,
      runs: byProject,
      settings: await _getSettings(db),
    );
  });

  static Future<List<DbHostCiProject>> _getProjects(SdbClient db) async {
    var projects = await hostCiProjectStore.findRecords(db);
    projects.sort((a, b) {
      var cmp = (a.added.v ?? 0).compareTo(b.added.v ?? 0);
      return cmp != 0 ? cmp : a.id.compareTo(b.id);
    });
    return projects;
  }

  /// Every project, in the order added.
  Future<List<DbHostCiProject>> getProjects() => session(_getProjects);

  /// One project, null when unknown.
  Future<DbHostCiProject?> getProject(String id) =>
      session((db) => hostCiProjectStore.record(id).get(db));

  /// Write a project (new or updated), [project] must have its id.
  Future<DbHostCiProject> putProject(DbHostCiProject project) =>
      session((db) => hostCiProjectStore.record(project.id).put(db, project));

  /// Read a project, change it with [update] and write it back, in one
  /// session; null when the project is unknown.
  Future<DbHostCiProject?> updateProject(
    String id,
    void Function(DbHostCiProject project) update,
  ) => session((db) async {
    var record = hostCiProjectStore.record(id);
    var project = await record.get(db);
    if (project == null) {
      return null;
    }
    update(project);
    return await record.put(db, project);
  });

  /// Add a project, ignored when it exists already (the existing record is
  /// returned).
  ///
  /// [root] is the git checkout when [path] is a sub folder of it,
  /// [cloneUrl] and [cloneRef] the remote and branch of a checkout cloned by
  /// Host CI.
  Future<DbHostCiProject> addProject({
    required String id,
    required String path,
    required String name,
    String? root,
    String? cloneUrl,
    String? cloneRef,
    DateTime? now,
  }) => session((db) async {
    var record = hostCiProjectStore.record(id);
    var existing = await record.get(db);
    if (existing != null) {
      return existing;
    }
    var project = DbHostCiProject()
      ..path.v = path
      ..name.v = name
      ..root.v = root
      ..cloneUrl.v = cloneUrl
      ..cloneRef.v = cloneRef
      ..added.v = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return await record.put(db, project);
  });

  /// Delete a project and its runs, returns what was deleted (for an undo),
  /// null when the project is unknown.
  Future<HostCiDeletedProject?> deleteProject(String id) => session((db) async {
    var project = await hostCiProjectStore.record(id).get(db);
    if (project == null) {
      return null;
    }
    var runs = await _getRuns(db, id);
    await hostCiRunStore.inTransaction(db, SdbTransactionMode.readWrite, (
      txn,
    ) async {
      for (var run in runs) {
        await hostCiRunStore.record(run.id).delete(txn);
      }
    });
    await hostCiProjectStore.record(id).delete(db);
    return HostCiDeletedProject(project: project, runs: runs);
  });

  /// Put a deleted project back, with its runs.
  Future<void> restoreProject(HostCiDeletedProject deleted) =>
      session((db) async {
        await hostCiProjectStore
            .record(deleted.project.id)
            .put(db, deleted.project);
        await hostCiRunStore.inTransaction(db, SdbTransactionMode.readWrite, (
          txn,
        ) async {
          for (var run in deleted.runs) {
            await hostCiRunStore.record(run.id).put(txn, run);
          }
        });
      });

  static Future<List<DbHostCiRun>> _getRuns(
    SdbClient db,
    String projectId,
  ) async {
    var records = await hostCiRunProjectIndex.findRecords(
      db,
      boundaries: SdbBoundaries.key(projectId),
    );
    var runs = records.map((record) => record.record).toList();
    runs.sort((a, b) => a.id.compareTo(b.id));
    return runs;
  }

  /// The runs of a project, the oldest first.
  Future<List<DbHostCiRun>> getRuns(String projectId) =>
      session((db) => _getRuns(db, projectId));

  /// One run, null when unknown.
  Future<DbHostCiRun?> getRun(int key) =>
      session((db) => hostCiRunStore.record(key).get(db));

  /// The most recent run of any project (running or not), null when none.
  Future<DbHostCiRun?> getLatestRun() => session((db) async {
    var record = await hostCiRunStartIndex.findRecord(db, descending: true);
    return record?.record;
  });

  /// The last run of a project that ended with a verdict (or an error), null
  /// when none: a cancelled run does not count.
  Future<DbHostCiRun?> getLastCompletedRun(String projectId) async =>
      hostCiLastCompletedRun(await getRuns(projectId));

  /// The last run of a project, whatever its status, null when never run.
  Future<DbHostCiRun?> getLastRun(String projectId) async {
    var runs = await getRuns(projectId);
    return runs.isEmpty ? null : runs.last;
  }

  /// Add a run, the project `lastRun` points to it.
  Future<DbHostCiRun> addRun(DbHostCiRun run) => session((db) async {
    var added = await hostCiRunStore.add(db, run);
    var projectId = run.project.v;
    if (projectId != null) {
      var record = hostCiProjectStore.record(projectId);
      var project = await record.get(db);
      if (project != null) {
        project.lastRun.v = added.id;
        await record.put(db, project);
      }
    }
    return added;
  });

  /// Write a run back.
  Future<void> putRun(DbHostCiRun run) =>
      session((db) => hostCiRunStore.record(run.id).put(db, run));

  /// Mark the open failure reports of a project validated (only [runId] when
  /// given); returns the runs validated.
  Future<List<DbHostCiRun>> validate(
    String projectId, {
    int? runId,
    required DateTime now,
  }) => session((db) async {
    var runs = hostCiOpenFailureRuns(await _getRuns(db, projectId));
    var validated = <DbHostCiRun>[];
    for (var run in runs) {
      if (runId == null || run.id == runId) {
        run.validated.v = now.millisecondsSinceEpoch;
        await hostCiRunStore.record(run.id).put(db, run);
        validated.add(run);
      }
    }
    return validated;
  });

  /// The runs left `running` by a process that is gone (closed or crashed
  /// mid-run) become errors ("interrupted"); [livePid] is the process
  /// running now (its run is left alone), null when none. Returns them.
  Future<List<DbHostCiRun>> recoverInterruptedRuns({
    int? livePid,
    DateTime? now,
  }) => session((db) async {
    var runs = await hostCiRunStore.findRecords(db);
    var interrupted = <DbHostCiRun>[];
    for (var run in runs) {
      if (run.isRunning && (livePid == null || run.pid.v != livePid)) {
        run
          ..status.v = HostCiRunStatus.error.name
          ..error.v = hostCiInterruptedError
          ..end.v =
              run.heartbeat.v ?? (now ?? DateTime.now()).millisecondsSinceEpoch;
        for (var step in run.stepList) {
          if (step.stepStatus == HostCiStepStatus.running ||
              step.stepStatus == HostCiStepStatus.pending) {
            step.status.v = HostCiStepStatus.cancelled.name;
          }
        }
        await hostCiRunStore.record(run.id).put(db, run);
        interrupted.add(run);
      }
    }
    return interrupted;
  });

  /// Keep the log of the last [logsKept] runs of a project and of its open
  /// failure reports, the older runs lose their `log` field; returns the log
  /// paths to delete.
  Future<List<String>> applyLogRetention(
    String projectId, {
    required int logsKept,
  }) => session((db) async {
    var runs = await _getRuns(db, projectId);
    var open = hostCiOpenFailureRuns(runs).map((run) => run.id).toSet();
    var withLog = runs.where((run) => run.log.v != null).toList();
    var removed = <String>[];
    if (withLog.length <= logsKept) {
      return removed;
    }
    for (var run in withLog.sublist(0, withLog.length - logsKept)) {
      if (open.contains(run.id)) {
        continue;
      }
      removed.add(run.log.v!);
      run.log.clear();
      await hostCiRunStore.record(run.id).put(db, run);
    }
    return removed;
  });

  static Future<DbHostCiSettings> _getSettings(SdbClient db) async =>
      await hostCiSettingsStore.record(hostCiSettingsKey).get(db) ??
      DbHostCiSettings();

  /// The settings, defaults when never written.
  Future<DbHostCiSettings> getSettings() => session(_getSettings);

  /// Write the settings.
  Future<void> setSettings(DbHostCiSettings settings) => session(
    (db) => hostCiSettingsStore.record(hostCiSettingsKey).put(db, settings),
  );

  /// Read the settings, change them with [update] and write them back, in
  /// one session.
  Future<DbHostCiSettings> updateSettings(
    void Function(DbHostCiSettings settings) update,
  ) => session((db) async {
    var settings = await _getSettings(db);
    update(settings);
    return await hostCiSettingsStore
        .record(hostCiSettingsKey)
        .put(db, settings);
  });

  /// True when the database holds no project and no run.
  Future<bool> isEmpty() => session((db) async {
    return (await hostCiProjectStore.findRecords(db, limit: 1)).isEmpty &&
        (await hostCiRunStore.findRecords(db, limit: 1)).isEmpty;
  });
}

/// The last run of [runs] (the oldest first) that ended with a verdict or
/// an error, null when none: a cancelled or interrupted run does not count.
DbHostCiRun? hostCiLastCompletedRun(List<DbHostCiRun> runs) =>
    HostCiVerdicts(runs).last;

/// A deleted project with its runs, to put it back.
class HostCiDeletedProject {
  /// The project record.
  final DbHostCiProject project;

  /// Its runs.
  final List<DbHostCiRun> runs;

  /// Creates a deleted project.
  HostCiDeletedProject({required this.project, required this.runs});

  /// The log paths of the runs (relative to the logs folder).
  List<String> get logPaths => [
    for (var run in runs)
      if (run.log.v != null) run.log.v!,
  ];
}
