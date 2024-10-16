import 'package:path/path.dart';
import 'package:process_run/stdio.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:tekartik_app_common_prefs/app_prefs.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_prj_tktools/src/tkpub.dart';

/// path prefs key.
const prefsKeyConfigExportPath = 'path';

/// Db config ref
class DbConfigRef extends DbStringRecordBase {
  /// git ref (dart3a)
  final gitRef = CvField<String>('gitRef');

  @override
  CvFields get fields => [gitRef];
}

/// Db package config
class TkPubDbPackage extends DbStringRecordBase {
  /// url
  final gitUrl = CvField<String>('gitUrl');

  /// path
  final gitPath = CvField<String>('gitPath');

  /// ref (optional, default to config)
  final gitRef = CvField<String>('gitRef');

  /// published (hosted)
  final published = CvField<String>('published');

  @override
  CvFields get fields => [gitUrl, gitPath, gitRef, published];
}

/// Config database.
class ConfigDb {
  /// the sembase db
  final Database db;

  /// Delete a package
  Future<bool> deletePackage(String id) async {
    if (tkPubPackagesStore.record(id).existsSync(db)) {
      await tkPubPackagesStore.record(id).delete(db);
      return true;
    }
    return false;
  }

  /// set/update a package
  Future<void> setPackage(TkPubDbPackage package) async {
    await tkPubPackagesStore.record(package.id).put(db, package);
  }

  /// Get a package
  Future<TkPubDbPackage> getPackage(String id, {bool? addMissingRef}) async {
    var package = await getPackageOrNull(id, addMissingRef: addMissingRef);
    if (package == null) {
      throw StateError('Package not found $id');
    }
    return package;
  }

  /// Get a package or null
  Future<TkPubDbPackage?> getPackageOrNull(String id,
      {bool? addMissingRef}) async {
    var package = await tkPubPackagesStore.record(id).get(db);
    if (package == null) {
      return null;
    }
    if (addMissingRef ?? false) {
      if (package.gitRef.isNull) {
        var defaultRef = await tkPubConfigRefRecord.get(db);
        package.gitRef.v = defaultRef?.gitRef.v;
      }
    }
    return package;
  }

  /// Constructor
  ConfigDb(this.db) {
    cvAddConstructor(TkPubDbPackage.new);
    cvAddConstructor(DbConfigRef.new);
  }

  /// Close the db
  Future<void> close() async {
    await db.close();
  }
}

/// Open the prefs
Future<Prefs> openPrefs() async {
  var prefsFactory = getPrefsFactory(packageName: 'com.tekartik.tkpub');
  return await prefsFactory.openPreferences('config.prefs');
}

/// Package store
var tkPubPackagesStore =
    cvStringRecordFactory.store<TkPubDbPackage>('packages');

/// Config store
var configStore = cvStringRecordFactory.store<DbRecord<String>>('config');

/// Config ref record.
var tkPubConfigRefRecord =
    configStore.cast<String, DbConfigRef>().record('ref');

late String _configExportPath;
var _initialized = false;
Future<Database> _tkpubDbOpen({String? configExportPath}) async {
  if (!_initialized) {
    configExportPath ??= await () async {
      return await tkPubGetConfigExportPath();
    }();

    if (configExportPath == null) {
      throw StateError('Not intialized, call tkpub_init first');
    } else {
      _configExportPath = configExportPath;
      _initialized = true;
    }
  }

  var factory = newDatabaseFactoryMemory();
  Database? db;
  var dbName = 'tkpub_config.db';
  var exportFile = File(_configExportPath);
  if (exportFile.existsSync()) {
    try {
      db = await importDatabaseAny(
          await exportFile.readAsLines(), factory, dbName);
    } catch (e) {
      stderr.writeln('error: $e');
    }
  }
  db ??= await factory.openDatabase(dbName);
  return db;
}

Future<void> _tkpubDbClose(Database db) async {
  var exportFile = File(_configExportPath);
  await Directory(dirname(exportFile.path)).create(recursive: true);
  await exportFile
      .writeAsString(exportLinesToJsonlString(await exportDatabaseLines(db)));
}

/// tkpub action on db, import & export
Future<T> tkPubDbAction<T>(Future<T> Function(ConfigDb db) action,
    {bool? write, String? configExportPath}) async {
  var db = await _tkpubDbOpen(configExportPath: configExportPath);
  try {
    return await action(ConfigDb(db));
  } finally {
    if (write ?? false) {
      await _tkpubDbClose(db);
    } else {
      await db.close();
    }
  }
}

/// Get all packages
Future<List<TkPubDbPackage>> tkPubGetAllPackages() async {
  return await tkPubDbAction((db) async {
    var packages = await tkPubPackagesStore.query().getRecords(db.db);
    return packages;
  });
}
