import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_prj_tktools/dtk.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk.dart';
export 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

/// Db config ref
class DbDtkDepConfigRef extends DbStringRecordBase {
  /// git ref (dart3a)
  final gitRef = CvField<String>('gitRef');

  @override
  CvFields get fields => [gitRef];
}

/// Db Dependency config
class DbDtkDepDependency extends DbStringRecordBase {
  /// min version
  final minVersion = CvField<String>('minVersion');

  @override
  CvFields get fields => [minVersion];
}

/// DtkDepConfig db
typedef DtkDepConfigDb = DtkConfigDb;

/// Config database.
extension DtkDepConfigDbExt on DtkConfigDb {
  /// the sembast db
  Database get db => database;

  /// Constructor
  void initBuilders() {
    _initBuilders();
  }

  /// Get config
  Future<DbDtkDepConfigRef?> getConfig() async {
    var config = await dtkDepDbConfigRefRecord.get(db);
    return config;
  }

  /// Set config
  Future<DbDtkDepConfigRef> setConfig(DbDtkDepConfigRef ref) async {
    var config = await dtkDepDbConfigRefRecord.put(db, ref);
    return config;
  }

  /// Get all Dependencies
  Future<List<DbDtkDepDependency>> getAllDependencies() async {
    return await dtkDepDbDependencyStore.query().getRecords(db);
  }

  /// Delete a Dependency
  Future<bool> deleteDependency(String id) async {
    if (dtkDepDbDependencyStore.record(id).existsSync(db)) {
      await dtkDepDbDependencyStore.record(id).delete(db);
      return true;
    }
    return false;
  }

  /// set/update a Dependency
  Future<DbDtkDepDependency> setDependency(
    String id,
    DbDtkDepDependency dependency,
  ) async {
    return await dtkDepDbDependencyStore.record(id).put(db, dependency);
  }

  /// Get a Dependency
  Future<DbDtkDepDependency> getDependency(String id) async {
    var dependency = await getDependencyOrNull(id);
    if (dependency == null) {
      throw StateError('Dependency not found $id');
    }
    return dependency;
  }

  /// Get a Dependency or null
  Future<DbDtkDepDependency?> getDependencyOrNull(String id) async {
    var dependency = await dtkDepDbDependencyStore.record(id).get(db);
    if (dependency == null) {
      return null;
    }
    return dependency;
  }
}

/// Dependency store
var dtkDepDbDependencyStore = cvStringStoreFactory.store<DbDtkDepDependency>(
  'dependency',
);

/// Config store
var dtkDepDbConfigStore = cvStringStoreFactory.store<DbRecord<String>>(
  'config',
);

/// Config ref record.
var dtkDepDbConfigRefRecord = dtkDepDbConfigStore
    .cast<String, DbDtkDepConfigRef>()
    .record('ref');

late String _configExportPath;
var _initialized = false;

void _initBuilders() {
  cvAddConstructors([DbDtkDepConfigRef.new, DbDtkDepDependency.new]);
}

Future<String> _dtkGetDepConfigExportPath({String? configExportPath}) async {
  if (!_initialized) {
    configExportPath ??= await dtkGetDepExportPath();

    if (configExportPath == null) {
      throw StateError(
        'Git config db not initialized, set global prefs $dtkDepExportPathGlobalPrefsKey',
      );
    } else {
      _configExportPath = configExportPath;
      _initialized = true;
    }
    _initBuilders();
  }
  return _configExportPath;
}

/// tkpub action on db, import & export
Future<T> dtkDepConfigDbAction<T>(
  Future<T> Function(DtkDepConfigDb db) action, {
  bool? write,
  String? configExportPath,
  bool? verbose,
}) async {
  var exportPath = await _dtkGetDepConfigExportPath(
    configExportPath: configExportPath,
  );
  return await dtkConfigDbAction(
    action,
    exportPath: exportPath,
    write: write,
    verbose: verbose,
  );
}

/// Get all Dependencies
Future<List<DbDtkDepDependency>> dtkDepGetAllDependencies() async {
  return await dtkDepConfigDbAction((configDb) async {
    return await configDb.getAllDependencies();
  });
}
