import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_common_utils/tags.dart';
import 'package:tekartik_prj_tktools/dtk.dart';

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

/// DtkGitConfig db
typedef DtkGitConfigDb = DtkConfigDb;

/// Config database.
extension DtkGitConfigDbExt on DtkConfigDb {
  /// the sembast db
  Database get db => database;

  /// Constructor
  void initBuilders() {
    _initBuilders();
  }

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
    DbDtkGitRepository repository,
  ) async {
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

  /// Close the db
  Future<void> close() async {
    await db.close();
  }
}

/// Repository store
var dtkGitDbRepositoryStore = cvStringStoreFactory.store<DbDtkGitRepository>(
  'repository',
);

/// Config store
var dtkGitDbConfigStore = cvStringStoreFactory.store<DbRecord<String>>(
  'config',
);

/// Config ref record.
var dtkGitDbConfigRefRecord = dtkGitDbConfigStore
    .cast<String, DbDtkGitConfigRef>()
    .record('ref');

late String _configExportPath;
var _initialized = false;

void _initBuilders() {
  cvAddConstructors([DbDtkGitConfigRef.new, DbDtkGitRepository.new]);
}

Future<String> _dtkGetGitConfigExportPath({String? configExportPath}) async {
  if (!_initialized) {
    configExportPath ??= await dtkGetGitExportPath();

    if (configExportPath == null) {
      throw StateError(
        'Git config db not initialized, set global prefs $dtkGitExportPathGlobalPrefsKey',
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
Future<T> dtkGitConfigDbAction<T>(
  Future<T> Function(DtkGitConfigDb db) action, {
  bool? write,
  String? configExportPath,
  bool? verbose,
}) async {
  var exportPath = await _dtkGetGitConfigExportPath(
    configExportPath: configExportPath,
  );
  return await dtkConfigDbAction(
    action,
    exportPath: exportPath,
    write: write,
    verbose: verbose,
  );
}

/// Get all repositories
Future<List<DbDtkGitRepository>> dtkGitGetAllRepositories({
  String? tagFilter,
}) async {
  return await dtkGitConfigDbAction((db) async {
    var allRepos = await dtkGitDbRepositoryStore.query().getRecords(db.db);
    if (tagFilter != null) {
      var tagsCondition = TagsCondition(tagFilter);
      allRepos =
          allRepos
              .where((repo) => tagsCondition.check(Tags.fromList(repo.tags.v)))
              .toList();
    }
    return allRepos;
  });
}
