import 'package:sembast/timestamp.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_app_sembast/sembast.dart';

/// Db timepoint
/// Time in history
class DbDtkTimepoint extends DbIntRecordBase {
  /// timestamp
  final timestamp = CvField<Timestamp>('timestamp');

  @override
  CvFields get fields => [timestamp];
}

/// Db status config
class DbDtkStatusConfig extends DbStringRecordBase {
  /// Current timepoint
  final currentTimepoint = CvField<int>('currentTimepoint');

  @override
  CvFields get fields => [currentTimepoint];
}

/// Not tried yet
const actionResultNone = 'none';

/// KO
const actionResultKo = 'ko';

/// Ok result
const actionResultOk = 'ok';

/// dtk action runner
const actionFindDartProjects = 'findDartProjects';

/// Find repos action
const actionFindRepos = 'findRepos';

/// Pub upgrade action
const actionPubUpgrade = 'pubUpgrade';

/// Pub upgrade action
const actionAnalyze = 'analyze';

/// Action
class DbDtkAction extends DbIntRecordBase {
  /// Associated timepoint
  final timepoint = CvField<int>('timepoint');

  /// timestamp
  final timestamp = CvField<Timestamp>('timestamp');

  /// action
  final action = CvField<String>('action');

  /// Main action
  final main = CvField<bool>('main');

  /// status (none, ok, ko)
  final status = CvField<String>('status');
  @override
  CvFields get fields => [timepoint, timestamp, action, status, main];
}

/// model
final dbDtkActionModel = DbDtkAction();

/// Find repos action
class DbDtkActionFindRepos extends DbDtkAction {
  /// gitHubTop
  final gitTop = CvField<String>('gitTop');

  /// Repos
  final repos = CvListField<String>('repos');
  @override
  CvFields get fields => [...super.fields, gitTop, repos];
}

/// Find repos action
class DbDtkActionFindDartProject extends DbDtkAction {
  /// repo
  final repo = CvField<String>('repo');

  /// Dart projects
  final dartProjects = CvListField<String>('dartProjects');
  @override
  CvFields get fields => [...super.fields, repo, dartProjects];
}

/// Find repos action
class DbDtkActionPubUpgrade extends DbDtkAction {
  /// repo/dartProjectPath
  final path = CvField<String>('path');

  @override
  CvFields get fields => [...super.fields, path];
}

/// Model
final dbDtkActionFindDartProjectModel = DbDtkActionFindDartProject();

/// The model
final dbDtkTimepointModel = DbDtkTimepoint();

/// Open the dtk status db
Future<DtkStatusDb> dtkStatusDbOpen() async {
  var factory = getDatabaseFactory(packageName: 'com.tekartik.dtk');
  var db = await factory.openDatabase('status.db');
  return DtkStatusDb(db);
}

/// Config database.
class DtkStatusDb {
  /// the sembast db
  final Database db;

  /// Create a DtkGitStatusDb
  DtkStatusDb(this.db) {
    cvAddConstructors([
      DbDtkTimepoint.new,
      DbDtkStatusConfig.new,
      DbDtkActionFindRepos.new,
      DbDtkActionFindDartProject.new,
      DbDtkActionPubUpgrade.new,
    ]);
    cvAddBuilder<DbDtkAction>((map) {
      var action = map[dbDtkActionModel.action.name] as String;
      switch (action) {
        case actionFindRepos:
          return DbDtkActionFindRepos();
        case actionFindDartProjects:
          return DbDtkActionFindDartProject();
        case actionPubUpgrade:
          return DbDtkActionPubUpgrade();
        default:
          return DbDtkAction();
      }
    });
  }

  CvQueryRef<int, DbDtkTimepoint> get _timepointQueryRef =>
      dbDtkTimepointStore.query(
          finder: Finder(sortOrders: [
        SortOrder(dbDtkTimepointModel.timestamp.name, false)
      ]));
  Future<DbDtkTimepoint?> _getLastTimepoint(Transaction txn) async {
    return await _timepointQueryRef.getRecord(txn);
  }

  Future<DbDtkTimepoint> _getOrCreateLastTimepoint(Transaction txn,
      {Timestamp? now}) async {
    return await _timepointQueryRef.getRecord(txn) ??
        _createTimepoint(txn, now: now);
  }

  /// Find when done for sub task
  Future<DbDtkActionFindRepos> getFindReposAction() async {
    return (await findAction<DbDtkActionFindRepos>(actionFindRepos))!;
  }

  /// Find when done for sub task
  Future<DbDtkActionFindDartProject> getFindDartProjectAction(
      {required String repo}) async {
    return (await findAction<DbDtkActionFindDartProject>(actionFindDartProjects,
        model: DbDtkActionFindDartProject()..repo.v = repo))!;
  }

  /// Find actions
  Future<T?> findAction<T extends DbDtkAction>(String action,
      {T? model}) async {
    return await db.transaction((txn) async {
      var timepointId = (await _getOrCreateLastTimepoint(txn)).id;
      Filter? filter;
      if (model != null) {
        filter = _filterFromModel(model as DbDtkAction);
      }
      return (await _findActions<T>(txn, timepointId, action, filter: filter))
          .firstOrNull;
    });
  }

  Future<T> _createAction<T extends DbDtkAction>(
      Transaction txn, int timepointId, String action,
      {required bool main, T? model}) async {
    var newAction = cvNewModel<T>()
      ..action.v = action
      ..timepoint.v = timepointId
      ..timestamp.v = Timestamp.now()
      ..status.v = actionResultNone
      ..main.v = main;
    if (model != null) {
      /// Copy fields
      for (var field in model.fields) {
        if (field.hasValue) {
          newAction.field(field.name)?.setValue(field.v);
        }
      }
    }

    return await dbDtkActionStore.castV<T>().add(txn, newAction);
  }

  Filter? _filterFromModel<T extends DbDtkAction>(T model) {
    var filters = <Filter>[];

    /// equality on fields
    for (var field in model.fields) {
      if (field.hasValue) {
        filters.add(Filter.equals(field.name, field.v));
      }
    }
    if (filters.isNotEmpty) {
      return Filter.and(filters);
    }
    return null;
  }

  /// Find or create action
  Future<T> findOrCreateAction<T extends DbDtkAction>(String action,
      {Filter? filter, T? model}) async {
    return await db.transaction((txn) async {
      var timepointId = (await _getOrCreateLastTimepoint(txn)).id;

      if (model != null) {
        filter = _filterFromModel(model);
      }
      var foundAction =
          (await _findActions<T>(txn, timepointId, action, filter: filter))
              .firstOrNull;

      return foundAction ??
          _createAction<T>(txn, timepointId, action,
              main: filter == null && model == null, model: model);
    });
  }

  /// Find actions
  Future<List<T>> findActions<T extends DbDtkAction>(String action) async {
    return await db.transaction((txn) async {
      var timepointId = (await _getOrCreateLastTimepoint(txn)).id;
      return await _findActions(txn, timepointId, action);
    });
  }

  /// Find actions
  Future<List<T>> _findActions<T extends DbDtkAction>(
      Transaction txn, int timepointId, String action,
      {Filter? filter}) async {
    var actions = await dbDtkActionStore
        .castV<T>()
        .query(
            finder: Finder(
                filter: Filter.and([
          Filter.equals(dbDtkActionModel.timepoint.name, timepointId),
          Filter.equals(dbDtkActionModel.action.name, action),
          if (filter != null)
            filter
          else
            Filter.equals(dbDtkActionModel.main.name, true),
        ])))
        .getRecords(txn);
    return actions;
  }

  /// Get the current timepoint
  Future<DbDtkTimepoint?> getCurrentTimepoint() async {
    return await db.transaction((txn) async {
      var timepointId = await _getConfigCurrentTimepointId(txn);
      if (timepointId != null) {
        var timepoint = await dbDtkTimepointStore.record(timepointId).get(txn);
        if (timepoint != null) {
          return timepoint;
        }
      }
      return await _getLastTimepoint(txn);
    });
  }

  /// Get the current timepoint id
  Future<int?> getCurrentTimepointId() async {
    return (await getCurrentTimepoint())?.id;
  }

  Future<void> _setCurrentTimepointId(Transaction txn, int? id) async {
    await dbDtkStatusConfigRecord.put(
        txn, DbDtkStatusConfig()..currentTimepoint.v = id);
  }

  /// Set the current timepoint
  Future<DbDtkTimepoint?> setCurrentTimepoint(int id) async {
    return await db.transaction((txn) async {
      var timepointId = await _getConfigCurrentTimepointId(txn);
      if (timepointId != id) {
        await _setCurrentTimepointId(txn, id);
      }
      var timepoint = await dbDtkTimepointStore.record(id).get(txn);
      if (timepoint != null) {
        return timepoint;
      }

      return await _getLastTimepoint(txn);
    });
  }

  /// Delete a Repository
  Future<DbDtkTimepoint> createTimepoint({Timestamp? now}) async {
    return await db.transaction((txn) async {
      return await _createTimepoint(txn, now: now);
    });
  }

  /// Delete a Repository
  Future<DbDtkTimepoint> _createTimepoint(Transaction txn,
      {Timestamp? now}) async {
    now ??= Timestamp.now();
    var record = DbDtkTimepoint()..timestamp.v = now;
    var timepoint = await dbDtkTimepointStore.add(txn, record);
    await _setCurrentTimepointId(txn, timepoint.id);
    return timepoint;
  }

  /// Get all timepoints
  Future<List<DbDtkTimepoint>> getTimepoints() async {
    return _timepointQueryRef.getRecords(db);
  }

  /// Get all timepoints
  Future<DbDtkTimepoint?> getTimepoint(int id) async {
    return dbDtkTimepointStore.record(id).get(db);
  }

  /// Delete timepoints
  Future<int> deleteTimepoints(
      {int? beforeId, Timestamp? beforeTimestamp}) async {
    return await db.transaction((txn) async {
      /// Find the before timestamp
      beforeTimestamp ??= beforeId != null
          ? (await dbDtkTimepointStore.record(beforeId).get(txn))?.timestamp.v
          : null;
      if (beforeTimestamp == null) {
        return 0;
      }
      var timepoints = await dbDtkTimepointStore.find(txn,
          finder: Finder(
              filter: Filter.lessThan(
                  dbDtkTimepointModel.timestamp.name, beforeTimestamp)));
      for (var timepoint in timepoints) {
        await dbDtkTimepointStore.record(timepoint.id).delete(txn);
        // TODO delete other things
      }
      return timepoints.length;
    });
  }

  /// Close the db
  Future<void> close() async {
    await db.close();
  }

  Future<int?> _getConfigCurrentTimepointId(Transaction txn) async {
    var config = await dbDtkStatusConfigRecord.get(txn);
    return config?.currentTimepoint.v;
  }

  /// Delete a timepoint
  Future<void> deleteTimepoint(int id) async {
    await db.transaction((txn) async {
      var currentTimepointId = await _getConfigCurrentTimepointId(txn);
      if (currentTimepointId == id) {
        await dbDtkStatusConfigRecord.put(
            txn, DbDtkStatusConfig()..currentTimepoint.v = null);
      }
      await dbDtkTimepointStore.record(id).delete(txn);
    });
  }
}

/// Repository store
var dbDtkTimepointStore = cvIntRecordFactory.store<DbDtkTimepoint>('timepoint');

/// action store
var dbDtkActionStore = cvIntRecordFactory.store<DbDtkAction>('action');

/// Config store
var dbDtkStatusConfigStore =
    cvStringRecordFactory.store<DbDtkStatusConfig>('config');

/// Config record
var dbDtkStatusConfigRecord = dbDtkStatusConfigStore.record('config');
