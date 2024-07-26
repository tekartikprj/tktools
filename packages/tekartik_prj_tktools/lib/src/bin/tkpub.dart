import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:tekartik_app_common_prefs/app_prefs.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_app_sembast/sembast.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';

import 'tkpub_add_cmd.dart';
import 'tkpub_config_cmd.dart';

//late bool verbose;

class TkpubCommand extends ShellBinCommand {
  TkpubCommand() : super(name: 'tkpub') {
    addCommand(TkpubConfigCommand());
    addCommand(_InitCommand());
    addCommand(TkpubAddCommand());
    addCommand(TkpubRemoveCommand());
    addCommand(TkpubClearCommand());
  }

  @override
  FutureOr<bool> onRun() {
    // print('verbose: $verbose');
    return false;
  }
}

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

/// Direct shell env Path dump run helper for testing.
Future<void> main(List<String> arguments) async {
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

class DbConfigRef extends DbStringRecordBase {
  final gitRef = CvField<String>('gitRef');

  @override
  CvFields get fields => [gitRef];
}

class DbPackage extends DbStringRecordBase {
  final gitUrl = CvField<String>('gitUrl');
  final gitPath = CvField<String>('gitPath');
  final gitRef = CvField<String>('gitRef');

  @override
  CvFields get fields => [gitUrl, gitPath, gitRef];
}

class ConfigDb {
  final Database db;

  Future<bool> deletePackage(String id) async {
    if (packagesStore.record(id).existsSync(db)) {
      await packagesStore.record(id).delete(db);
      return true;
    }
    return false;
  }

  Future<void> setPackage(DbPackage package) async {
    await packagesStore.record(package.id).put(db, package);
  }

  Future<DbPackage> getPackage(String id) async {
    var package = await getPackageOrNull(id);
    if (package == null) {
      throw StateError('Package not found $id');
    }
    return package;
  }

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

  ConfigDb(this.db);
}

Future<Prefs> openPrefs() async {
  var prefsFactory = getPrefsFactory(packageName: 'com.tekartik.tkpub');
  return await prefsFactory.openPreferences('config.prefs');
}

var packagesStore = cvStringRecordFactory.store<DbPackage>('packages');
var configStore = cvStringRecordFactory.store<DbRecord<String>>('config');
var configRefRecord = configStore.cast<String, DbConfigRef>().record('ref');

late String _configExportPath;
var initialized = false;
Future<Database> _tkpubDbOpen() async {
  if (!initialized) {
    var prefs = await openPrefs();
    var prefsPath = prefs.getString(prefsKeyPath);
    if (prefsPath == null) {
      throw StateError('Not intialized, call tkpub_init first');
    } else {
      cvAddConstructor(DbPackage.new);
      cvAddConstructor(DbConfigRef.new);
      _configExportPath = prefsPath;
      initialized = true;
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
      print('error: $e');
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

Future<void> tkpubDbAction(Future<void> Function(ConfigDb db) action,
    {bool? write}) async {
  var db = await _tkpubDbOpen();
  try {
    await action(ConfigDb(db));
  } finally {
    if (write ?? false) {
      await _tkpubDbClose(db);
    } else {
      await db.close();
    }
  }
}
