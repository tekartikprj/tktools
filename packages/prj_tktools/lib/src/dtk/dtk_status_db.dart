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

/// Action
class DbDtkAction extends DbIntRecordBase {
  /// Associated timepoint
  final timepoint = CvField<int>('timepoint');

  /// timestamp
  final timestamp = CvField<Timestamp>('timestamp');

  /// action
  final action = CvField<String>('action');

  /// result
  final result = CvField<String>('result');
  @override
  CvFields get fields => [timepoint, timestamp, action, result];
}

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
    cvAddConstructors([DbDtkTimepoint.new, DbDtkStatusConfig.new]);
  }

  CvQueryRef<int, DbDtkTimepoint> get _timepointQueryRef =>
      dbDtkTimepointStore.query(
          finder: Finder(sortOrders: [
        SortOrder(dbDtkTimepointModel.timestamp.name, false)
      ]));
  Future<DbDtkTimepoint?> _getLastTimepoint(Transaction txn) async {
    return await _timepointQueryRef.getRecord(txn);
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
      now ??= Timestamp.now();
      var record = DbDtkTimepoint()..timestamp.v = now;
      var timepoint = await dbDtkTimepointStore.add(txn, record);
      await _setCurrentTimepointId(txn, timepoint.id);
      return timepoint;
    });
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

/// Config store
var dbDtkStatusConfigStore =
    cvStringRecordFactory.store<DbDtkStatusConfig>('config');

/// Config record
var dbDtkStatusConfigRecord = dbDtkStatusConfigStore.record('config');
