import 'package:fs_shim/utils/io/read_write.dart';
import 'package:path/path.dart';
import 'package:process_run/stdio.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';

/// Dtk opened config db
@sealed
class DtkConfigDb {
  /// the sembast db (in memory, will be written back to the export file)
  final Database database;

  /// Export path
  final String? exportPath;

  /// true for write mode
  final bool write;

  /// True for verbose mode
  final bool verbose;

  /// Constructor
  const DtkConfigDb({
    required this.database,
    this.exportPath,
    bool? write,
    bool? verbose,
  }) : write = write ?? false,
       verbose = verbose ?? false;
}

Future<DtkConfigDb> _dtkConfigDbOpen({
  required String exportPath,
  bool? write,
  bool? verbose,
}) async {
  var factory = newDatabaseFactoryMemory();
  verbose ??= false;
  Database? db;
  var dbName = 'tmp.db';
  var exportFile = File(exportPath);
  if (verbose) {
    stderr.writeln('importing $exportPath');
  }
  if (exportFile.existsSync()) {
    try {
      db = await importDatabaseAny(
        await exportFile.readLines(),
        factory,
        dbName,
      );
    } catch (e) {
      stderr.writeln('error: $e, deleting $exportPath');
    }
  }
  db ??= await factory.openDatabase(dbName);
  return DtkConfigDb(
    database: db,
    exportPath: exportPath,
    write: write ?? false,
    verbose: verbose,
  );
}

Future<void> _dtkGitConfigDbClose(DtkConfigDb db) async {
  if (db.write) {
    var exportFile = File(db.exportPath!);
    var parentDir = Directory(dirname(exportFile.path));
    if (!(parentDir.existsSync())) {
      await parentDir.create(recursive: true);
    }
    await Directory(dirname(exportFile.path)).create(recursive: true);
    if (db.verbose) {
      stderr.writeln('exporting ${exportFile.path}');
    }
    await exportFile.writeLines(
      exportLinesToJsonStringList(await exportDatabaseLines(db.database)),
    );
  }
  await db.database.close();
}

/// tkpub action on db, import & export
Future<T> dtkConfigDbAction<T>(
  Future<T> Function(DtkConfigDb configDb) action, {
  bool? write,
  required String exportPath,
  bool? verbose,
}) async {
  var db = await _dtkConfigDbOpen(
    exportPath: exportPath,
    write: write,
    verbose: verbose,
  );
  try {
    return await action(db);
  } finally {
    await _dtkGitConfigDbClose(db);
  }
}
