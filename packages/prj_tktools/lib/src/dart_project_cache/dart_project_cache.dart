import 'dart:async';

import 'package:fs_shim/fs_shim.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';

import 'dart_project.dart';
import 'dart_project_cache_db.dart';
import 'dart_project_scan_task.dart';
import 'dart_project_scanner.dart';
import 'dart_project_search.dart';

/// A refresh of a folder of the cache: a scan, saved once done.
///
/// Refreshing a folder already being refreshed joins the running refresh,
/// see [DartProjectCache.refresh].
class DartProjectCacheRefresh {
  /// Canonical path of the folder refreshed.
  final String path;

  late final DartProjectScanTask _task;
  final _done = Completer<DartProjectScanResult>();
  DartProjectScanResult? _found;

  DartProjectCacheRefresh._(this.path);

  /// What was found so far, everything once done.
  DartProjectScanResult get found =>
      _found ??
      DartProjectScanResult(
        path: path,
        projects: const [],
        errors: const [],
        refreshed: DateTime.now(),
      );

  /// True once [cancel] was called, nothing is saved then.
  bool get cancelled => _task.cancelled;

  /// True once the refresh ended (saved, or cancelled).
  bool get isDone => _done.isCompleted;

  /// What was found, once saved (or cancelled). Never throws, a failed save
  /// is reported in [DartProjectScanResult.errors].
  Future<DartProjectScanResult> get done => _done.future;

  /// Stop the scan, the cache is left as it was.
  void cancel() => _task.cancel();

  @override
  String toString() => 'refresh $path';
}

/// Local cache of the dart projects of some folder trees.
///
/// The cache holds the projects of the folders that were scanned (their
/// whole tree): displaying any folder below a scanned one is instantaneous,
/// it is only scanned again on demand ([refresh]). A folder never scanned
/// is scanned the first time ([indexIfNeeded]).
///
/// Every record is keyed by its canonical path. The folders are scanned
/// through [fs], so that the cache works on any file system, the io one in a
/// background isolate (see [startDartProjectScan]).
///
/// A local cache only, it is never exported.
class DartProjectCache {
  /// Default database name.
  static const defaultDbName = 'dart_project_cache.db';

  /// The sdb database.
  final SdbDatabase database;

  /// The file system scanned.
  final FileSystem fs;

  /// The minimum time between 2 progress notifications of a refresh
  /// ([onRefresh]), so that a user interface displaying it is not rebuilt for
  /// every project found.
  final Duration progressInterval;

  /// Whether the folders are scanned in a background isolate, by default
  /// for the io file system.
  final bool? scanInIsolate;

  final _refreshes = <String, DartProjectCacheRefresh>{};
  final _refreshController =
      StreamController<DartProjectCacheRefresh>.broadcast();
  final _changeController = StreamController<String>.broadcast();

  /// Wraps an open [database].
  DartProjectCache(
    this.database, {
    FileSystem? fs,
    this.progressInterval = defaultProgressInterval,
    this.scanInIsolate,
  }) : fs = fs ?? fileSystemDefault;

  /// Default [progressInterval].
  static const defaultProgressInterval = Duration(milliseconds: 200);

  /// Open the cache database using [factory] (typically a local, app scoped,
  /// sdb factory), the folders are scanned through [fs] (the default one when
  /// null).
  static Future<DartProjectCache> open(
    SdbFactory factory, {
    FileSystem? fs,
    String dbName = defaultDbName,
    Duration progressInterval = defaultProgressInterval,
    bool? scanInIsolate,
  }) async {
    initCvDartProjectCache();
    var database = await factory.openDatabase(
      dbName,
      options: SdbOpenDatabaseOptions(
        version: dartProjectCacheVersion,
        schema: dartProjectCacheSchema,
      ),
    );
    return DartProjectCache(
      database,
      fs: fs,
      progressInterval: progressInterval,
      scanInIsolate: scanInIsolate,
    );
  }

  /// Canonical absolute path of [path], the key of the cache.
  String canonicalPath(String path) => dartProjectCanonicalPath(fs, path);

  /// Every time a refresh starts, finds a project or ends.
  Stream<DartProjectCacheRefresh> get onRefresh => _refreshController.stream;

  /// The folder saved, every time the cache changes.
  Stream<String> get onChanged => _changeController.stream;

  /// The refreshes running.
  List<DartProjectCacheRefresh> get refreshes => _refreshes.values.toList();

  /// The folders scanned, sorted by path.
  Future<List<DartProjectFolderInfo>> getFolders() async {
    var records = await dartProjectFolderStore.findRecords(database);
    return records.map((record) => record.toInfo()).toList();
  }

  /// The top folders of the cache: the folders scanned that are not below
  /// another one, sorted by path.
  Future<List<DartProjectFolderInfo>> getTopFolders() async {
    var tops = <DartProjectFolderInfo>[];
    for (var folder in await getFolders()) {
      if (!tops.any((top) => _isWithinOrSame(top.path, folder.path))) {
        tops.add(folder);
      }
    }
    return tops;
  }

  /// The folder scanned holding [path] (or [path] itself), the deepest one:
  /// it tells when [path] was scanned. Null when [path] was never scanned.
  Future<DartProjectFolderInfo?> getIndexedFolder(String path) async {
    var folder = canonicalPath(path);
    while (true) {
      var record = await dartProjectFolderStore.record(folder).get(database);
      if (record != null) {
        return record.toInfo();
      }
      var parent = fs.path.dirname(folder);
      if (parent == folder) {
        return null;
      }
      folder = parent;
    }
  }

  /// The project at [path], null when not in the cache.
  Future<DartProjectInfo?> getProject(String path) async =>
      (await dartProjectStore.record(canonicalPath(path)).get(database))
          ?.toInfo();

  /// The projects of the folder [path] (itself included), sorted by path,
  /// every project of the cache when null.
  Future<List<DartProjectInfo>> getProjects([String? path]) async {
    if (path == null) {
      var records = await dartProjectStore.findRecords(database);
      return records.map((record) => record.toInfo()).toList();
    }
    var folder = canonicalPath(path);
    return await dartProjectStore.inTransaction(
      database,
      SdbTransactionMode.readOnly,
      (txn) async {
        var self = await dartProjectStore.record(folder).get(txn);
        var below = await dartProjectStore.findRecords(
          txn,
          boundaries: _withinBoundaries(folder),
        );
        return [?self?.toInfo(), for (var record in below) record.toInfo()];
      },
    );
  }

  /// The git repositories of the folder [path] (itself included), sorted by
  /// path, every repository of the cache when null.
  Future<List<DartProjectGitFolderInfo>> getGitFolders([String? path]) async {
    if (path == null) {
      var records = await dartProjectGitStore.findRecords(database);
      return records.map((record) => record.toInfo()).toList();
    }
    var folder = canonicalPath(path);
    return await dartProjectGitStore.inTransaction(
      database,
      SdbTransactionMode.readOnly,
      (txn) async {
        var self = await dartProjectGitStore.record(folder).get(txn);
        var below = await dartProjectGitStore.findRecords(
          txn,
          boundaries: _withinBoundaries(folder),
        );
        return [?self?.toInfo(), for (var record in below) record.toInfo()];
      },
    );
  }

  /// The git repository holding [path] (or [path] itself), null when none is
  /// in the cache.
  Future<DartProjectGitFolderInfo?> getGitFolder(String path) async {
    var folder = canonicalPath(path);
    while (true) {
      var record = await dartProjectGitStore.record(folder).get(database);
      if (record != null) {
        return record.toInfo();
      }
      var parent = fs.path.dirname(folder);
      if (parent == folder) {
        return null;
      }
      folder = parent;
    }
  }

  /// The projects matching [query], the closest to [from] first, see
  /// [searchDartProjects].
  Future<List<DartProjectInfo>> search(
    String query, {
    String? from,
    int? limit,
  }) async => searchDartProjects(
    await getProjects(),
    query,
    from: from == null ? null : canonicalPath(from),
    limit: limit,
    context: fs.path,
  );

  /// Scan the folder [path] again, the cache of the whole folder is replaced
  /// once done.
  ///
  /// A refresh of [path] (or of a folder holding it) already running is
  /// joined: it is returned instead.
  DartProjectCacheRefresh refresh(String path) {
    var folder = canonicalPath(path);
    for (var running in _refreshes.values) {
      if (_isWithinOrSame(running.path, folder)) {
        return running;
      }
    }
    var refresh = DartProjectCacheRefresh._(folder);
    refresh._task = startDartProjectScan(
      fs,
      folder,
      isolate: scanInIsolate,
      progressInterval: progressInterval,
      onProgress: (found) {
        refresh._found = found;
        _refreshController.add(refresh);
      },
    );
    _refreshes[folder] = refresh;
    _refreshController.add(refresh);
    unawaited(_run(refresh));
    return refresh;
  }

  /// Scan [path] when it was never scanned (nor a folder holding it).
  ///
  /// Returns the refresh started (or joined), null when [path] is already in
  /// the cache.
  Future<DartProjectCacheRefresh?> indexIfNeeded(String path) async {
    var folder = canonicalPath(path);
    for (var running in _refreshes.values) {
      if (_isWithinOrSame(running.path, folder)) {
        return running;
      }
    }
    if (await getIndexedFolder(folder) != null) {
      return null;
    }
    return refresh(folder);
  }

  Future<void> _run(DartProjectCacheRefresh refresh) async {
    var result = await refresh._task.result;
    if (!result.cancelled) {
      try {
        await save(result);
      } catch (e) {
        result = result.withErrors(['${result.path}: $e']);
      }
    }
    refresh._found = result;
    _refreshes.remove(refresh.path);
    refresh._done.complete(result);
    _refreshController.add(refresh);
  }

  /// Replace the cache of the folder scanned by [result] (its whole tree).
  Future<void> save(DartProjectScanResult result) async {
    var folder = result.path;
    var within = _withinBoundaries(folder);
    await database.inStoresTransaction(_stores, SdbTransactionMode.readWrite, (
      txn,
    ) async {
      await _deleteWithin(txn, folder, within);
      for (var project in result.projects) {
        await dartProjectStore
            .record(project.path)
            .put(txn, dbDartProjectFrom(project));
      }
      for (var git in result.gitFolders) {
        await dartProjectGitStore
            .record(git.path)
            .put(txn, dbDartProjectGitFrom(git));
      }
      // The folders scanned before below this one are replaced by it.
      await dartProjectFolderStore.delete(txn, boundaries: within);
      await dartProjectFolderStore
          .record(folder)
          .put(
            txn,
            DbDartProjectFolder()
              ..refreshed.v = result.refreshed.millisecondsSinceEpoch,
          );
    });
    _changeController.add(folder);
  }

  /// Forget the folder [path] and its projects.
  ///
  /// The folders scanned below it are forgotten too, a folder holding it is
  /// kept: [path] is then simply not in the cache anymore.
  Future<void> delete(String path) async {
    var folder = canonicalPath(path);
    var within = _withinBoundaries(folder);
    await database.inStoresTransaction(_stores, SdbTransactionMode.readWrite, (
      txn,
    ) async {
      await _deleteWithin(txn, folder, within);
      await dartProjectFolderStore.record(folder).delete(txn);
      await dartProjectFolderStore.delete(txn, boundaries: within);
    });
    _changeController.add(folder);
  }

  /// Stop the refreshes and close the database.
  Future<void> close() async {
    var running = refreshes;
    for (var refresh in running) {
      refresh.cancel();
    }
    await Future.wait(running.map((refresh) => refresh.done));
    await _refreshController.close();
    await _changeController.close();
    await database.close();
  }

  /// The stores written by a save.
  List<SdbStoreRef> get _stores => [
    dartProjectStore.rawRef,
    dartProjectGitStore.rawRef,
    dartProjectFolderStore.rawRef,
  ];

  /// Delete the projects and the git repositories of [folder] (itself
  /// included).
  Future<void> _deleteWithin(
    SdbClient txn,
    String folder,
    SdbBoundaries<String> within,
  ) async {
    await dartProjectStore.record(folder).delete(txn);
    await dartProjectStore.delete(txn, boundaries: within);
    await dartProjectGitStore.record(folder).delete(txn);
    await dartProjectGitStore.delete(txn, boundaries: within);
  }

  SdbBoundaries<String> _withinBoundaries(String folder) =>
      dartProjectCacheWithinBoundaries(folder, separator: fs.path.separator);

  /// True when [path] is [folder] or below it.
  bool _isWithinOrSame(String folder, String path) =>
      folder == path || fs.path.isWithin(folder, path);
}
