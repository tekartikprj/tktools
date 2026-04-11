import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/dtk.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk.dart';
export 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

var _initialized = false;
late String _configExportPath;
Future<String> _dtkGetHostEnvConfigExportPath({
  @visibleForTesting String? configExportPath,
}) async {
  if (!_initialized) {
    _configExportPath = await dtkGetHostEnvExportPath();
  }
  return _configExportPath;
}

/// tkpub action on db, import & export
Future<T> dtkHostEnvConfigDbAction<T>(
  Future<T> Function(DtkGitConfigDb db) action, {
  bool? write,
  @visibleForTesting String? configExportPath,
  bool? verbose,
}) async {
  var exportPath = await _dtkGetHostEnvConfigExportPath(
    configExportPath: configExportPath,
  );
  return await dtkConfigDbAction(
    action,
    exportPath: exportPath,
    write: write,
    verbose: verbose,
  );
}

final _varStore = StoreRef<String, String>('var');

/// Get host env var
Future<String?> dtkHostEnvVarGetOrNull(String key) async {
  return await dtkHostEnvConfigDbAction((db) async {
    var database = db.database;
    return await _varStore.record(key).get(database);
  });
}

/// Get host env var
Future<String> dtkHostEnvVarGet(String key) async {
  var value = await dtkHostEnvVarGetOrNull(key);
  if (value == null) {
    throw StateError('host env var $key not found');
  }
  return value;
}

/// Set host env var
Future<void> dtkHostEnvVarSet(String key, String value) async {
  await dtkHostEnvConfigDbAction((db) async {
    var database = db.database;
    await _varStore.record(key).put(database, value);
  }, write: true);
}
