import 'package:path/path.dart';
import 'package:process_run/stdio.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_common_utils/tags.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk.dart';

/// Db config ref
class DbDtkGitConfigRef extends DbStringRecordBase {
  /// git ref (dart3a)
  final gitRef = CvField<String>('gitRef');

  @override
  CvFields get fields => [gitRef];
}

/// Db Repository config
class DbDtkGitRepository extends DbStringRecordBase {
  /// url
  final gitUrl = CvField<String>('gitUrl');

  /// ref (optional, default to config)
  final gitRef = CvField<String>('gitRef');

  /// tags (public, main, project specific)
  final tags = CvListField<String>('tags');
  @override
  CvFields get fields => [gitUrl, gitRef, tags];
}

/// Extension
extension DbDtkGitRepositoryExt on DbDtkGitRepository {
  /// Add a tag, returns [true] if added, [false] if already there
  bool addTag(String tag) {
    var tags = Tags.fromList(this.tags.v);
    if (tags.add(tag)) {
      this.tags.v = (tags..sort()).toListOrNull();
      return true;
    }
    return false;
  }

  /// Remove a tag, returns [true] if removed, [false] if not there
  bool removeTag(String tag) {
    var tags = Tags.fromList(this.tags.v);
    if (tags.remove(tag)) {
      // No need to sort
      this.tags.v = tags.toListOrNull();
      return true;
    }
    return false;
  }

  /// Get the unique name from the git url
  String get uniqueName => dtkGitUniqueNameFromUrl(gitUrl.v!);
}

/// Config database.
class DtkGitConfigDb {
  /// the sembast db
  final Database db;

  /// Get all repositories
  Future<List<DbDtkGitRepository>> getAllRepositories() async {
    return await dtkGitDbRepositoryStore.query().getRecords(db);
  }

  /// Delete a Repository
  Future<bool> deleteRepository(String id) async {
    if (dtkGitDbRepositoryStore.record(id).existsSync(db)) {
      await dtkGitDbRepositoryStore.record(id).delete(db);
      return true;
    }
    return false;
  }

  /// set/update a Repository
  Future<DbDtkGitRepository> setRepository(
      DbDtkGitRepository repository) async {
    var id =
        repository.idOrNull ?? dtkGitUniqueNameFromUrl(repository.gitUrl.v!);
    return await dtkGitDbRepositoryStore.record(id).put(db, repository);
  }

  /// Get a Repository
  Future<DbDtkGitRepository> getRepository(String id) async {
    var repository = await getRepositoryOrNull(id);
    if (repository == null) {
      throw StateError('Repository not found $id');
    }
    return repository;
  }

  /// Get a Repository or null
  Future<DbDtkGitRepository?> getRepositoryOrNull(String id) async {
    var repository = await dtkGitDbRepositoryStore.record(id).get(db);
    if (repository == null) {
      return null;
    }
    return repository;
  }

  /// Constructor
  DtkGitConfigDb(this.db) {
    cvAddConstructors([DbDtkGitConfigRef.new, DbDtkGitRepository.new]);
  }

  /// Close the db
  Future<void> close() async {
    await db.close();
  }
}

/// Repository store
var dtkGitDbRepositoryStore =
    cvStringRecordFactory.store<DbDtkGitRepository>('repository');

/// Config store
var dtkGitDbConfigStore =
    cvStringRecordFactory.store<DbRecord<String>>('config');

/// Config ref record.
var dtkGitDbConfigRefRecord =
    dtkGitDbConfigStore.cast<String, DbDtkGitConfigRef>().record('ref');

late String _configExportPath;
var _initialized = false;
Future<Database> _dtkGitConfigDbOpen({String? configExportPath}) async {
  if (!_initialized) {
    configExportPath ??= await dtkGetGitExportPath();

    if (configExportPath == null) {
      throw StateError('Not intialized');
    } else {
      cvAddConstructor(DbDtkGitRepository.new);
      cvAddConstructor(DbDtkGitConfigRef.new);
      _configExportPath = configExportPath;
      _initialized = true;
    }
  }

  var factory = newDatabaseFactoryMemory();
  Database? db;
  var dbName = 'dtk_git_tmp.db';
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

Future<void> _dtkGitConfigDbClose(Database db) async {
  var exportFile = File(_configExportPath);
  await Directory(dirname(exportFile.path)).create(recursive: true);
  await exportFile
      .writeAsString(exportLinesToJsonlString(await exportDatabaseLines(db)));
}

/// tkpub action on db, import & export
Future<T> dtkGitConfigDbAction<T>(Future<T> Function(DtkGitConfigDb db) action,
    {bool? write, String? configExportPath}) async {
  var db = await _dtkGitConfigDbOpen(configExportPath: configExportPath);
  try {
    return await action(DtkGitConfigDb(db));
  } finally {
    if (write ?? false) {
      await _dtkGitConfigDbClose(db);
    } else {
      await db.close();
    }
  }
}

/// Get all repositories
Future<List<DbDtkGitRepository>> dtkGitGetAllRepositories(
    {String? tagFilter}) async {
  return await dtkGitConfigDbAction((db) async {
    var allRepos = await dtkGitDbRepositoryStore.query().getRecords(db.db);
    if (tagFilter != null) {
      var tagsCondition = TagsCondition(tagFilter);
      allRepos = allRepos
          .where((repo) => tagsCondition.check(Tags.fromList(repo.tags.v)))
          .toList();
    }
    return allRepos;
  });
}
