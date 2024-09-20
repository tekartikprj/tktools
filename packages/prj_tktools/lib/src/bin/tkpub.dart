import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:tekartik_app_common_prefs/app_prefs.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_app_sembast/sembast.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub_copy_files_cmd.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub_list_cmd.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub_symlink_cmd.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:tekartik_prj_tktools/src/version.dart';

import 'tkpub_add_cmd.dart';
import 'tkpub_config_cmd.dart';

//late bool verbose;
/// tkpub command
class TkpubCommand extends ShellBinCommand {
  /// tkpub command
  TkpubCommand() : super(name: 'tkpub', version: packageVersion) {
    addCommand(TkpubConfigCommand());
    addCommand(_InitCommand());
    addCommand(TkpubAddCommand());
    addCommand(TkpubRemoveCommand());
    addCommand(TkpubListCommand());
    addCommand(TkpubClearCommand());
    addCommand(TkpubSymlinkCommand());
    addCommand(TkpubCopyFilesCommand());
  }

  @override
  FutureOr<bool> onRun() {
    // print('verbose: $verbose');
    return false;
  }
}

/// path prefs key.
const prefsKeyPath = 'path';

class _InitCommand extends ShellBinCommand {
  _InitCommand()
      : super(name: 'init', parser: ArgParser(allowTrailingOptions: true));

  @override
  FutureOr<bool> onRun() async {
    var rest = results.rest;
    if (rest.length != 1) {
      throw ArgumentError('One argument expected (path)');
    }
    var prefs = await openPrefs();
    prefs.setString(prefsKeyPath, rest.first);
    return true;
  }
}

/// Compat.
Future<void> main(List<String> arguments) => tkpubMain(arguments);

/// Direct shell env Path dump run helper for testing.
Future<void> tkpubMain(List<String> arguments) async {
  try {
    await TkpubCommand().parseAndRun(arguments);
  } catch (e) {
    var verbose = arguments.contains('-v') || arguments.contains('--verbose');
    if (verbose) {
      rethrow;
    }
    stderr.writeln(e);
    exit(1);
  }
}

/// Db config ref
class DbConfigRef extends DbStringRecordBase {
  /// git ref (dart3a)
  final gitRef = CvField<String>('gitRef');

  @override
  CvFields get fields => [gitRef];
}

/// Db package config
class DbPackage extends DbStringRecordBase {
  /// url
  final gitUrl = CvField<String>('gitUrl');

  /// path
  final gitPath = CvField<String>('gitPath');

  /// ref (optional, default to config)
  final gitRef = CvField<String>('gitRef');

  @override
  CvFields get fields => [gitUrl, gitPath, gitRef];
}

/// Config database.
class ConfigDb {
  /// the sembase db
  final Database db;

  /// Delete a package
  Future<bool> deletePackage(String id) async {
    if (packagesStore.record(id).existsSync(db)) {
      await packagesStore.record(id).delete(db);
      return true;
    }
    return false;
  }

  /// set/update a package
  Future<void> setPackage(DbPackage package) async {
    await packagesStore.record(package.id).put(db, package);
  }

  /// Get a package
  Future<DbPackage> getPackage(String id) async {
    var package = await getPackageOrNull(id);
    if (package == null) {
      throw StateError('Package not found $id');
    }
    return package;
  }

  /// Get a package or null
  Future<DbPackage?> getPackageOrNull(String id) async {
    var package = await packagesStore.record(id).get(db);
    if (package == null) {
      return null;
    }
    if (package.gitRef.isNull) {
      var defaultRef = await configRefRecord.get(db);
      package.gitRef.v = defaultRef?.gitRef.v;
    }
    return package;
  }

  /// Constructor
  ConfigDb(this.db);
}

/// Open the prefs
Future<Prefs> openPrefs() async {
  var prefsFactory = getPrefsFactory(packageName: 'com.tekartik.tkpub');
  return await prefsFactory.openPreferences('config.prefs');
}

/// Package store
var packagesStore = cvStringRecordFactory.store<DbPackage>('packages');

/// Config store
var configStore = cvStringRecordFactory.store<DbRecord<String>>('config');

/// Config ref record.
var configRefRecord = configStore.cast<String, DbConfigRef>().record('ref');

late String _configExportPath;
var _initialized = false;
Future<Database> _tkpubDbOpen() async {
  if (!_initialized) {
    var prefs = await openPrefs();
    var prefsPath = prefs.getString(prefsKeyPath);
    if (prefsPath == null) {
      throw StateError('Not intialized, call tkpub_init first');
    } else {
      cvAddConstructor(DbPackage.new);
      cvAddConstructor(DbConfigRef.new);
      _configExportPath = prefsPath;
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
Future<T> tkpubDbAction<T>(Future<T> Function(ConfigDb db) action,
    {bool? write}) async {
  var db = await _tkpubDbOpen();
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
