import 'package:tekartik_app_common_prefs/app_prefs.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_prj_tktools/dtk.dart';
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
typedef TkPubConfigDb = DtkConfigDb;

/// Helpers
extension TkPubConfigDbExt on TkPubConfigDb {
  /// the sembase db
  Database get db => database;

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
  void initBuilders() {
    _initBuilders();
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

void _initBuilders() {
  cvAddConstructors([TkPubDbPackage.new, DbConfigRef.new]);
}

Future<String> _tkPubGetConfigExportPath({String? configExportPath}) async {
  if (!_initialized) {
    configExportPath ??= await tkPubGetConfigExportPath();

    if (configExportPath == null) {
      throw StateError('Not intialized, call tkpub_init first');
    } else {
      // cvAddConstructors([DbDtkGitConfigRef.new, DbDtkGitRepository.new]);
      _configExportPath = configExportPath;
      _initialized = true;
    }
    _initBuilders();
  }
  return _configExportPath;
}

/// tkpub action on db, import & export
Future<T> tkPubDbAction<T>(Future<T> Function(DtkGitConfigDb db) action,
    {bool? write, String? configExportPath, bool? verbose}) async {
  var exportPath =
      await _tkPubGetConfigExportPath(configExportPath: configExportPath);
  return dtkConfigDbAction(action,
      exportPath: exportPath, write: write, verbose: verbose);
}

/// Get all packages
Future<List<TkPubDbPackage>> tkPubGetAllPackages() async {
  return await tkPubDbAction((db) async {
    var packages = await tkPubPackagesStore.query().getRecords(db.database);
    return packages;
  });
}
