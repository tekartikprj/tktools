import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';

import 'dart_project.dart';

/// A dart project (or a local workspace), the key is the canonical path of
/// its folder.
class DbDartProject extends ScvStringRecordBase {
  /// Package name (the folder name for a local workspace).
  final name = CvField<String>('name');

  /// A [DartProjectKind] name.
  final kind = CvField<String>('kind');

  /// When the project was read from the disk, in milliseconds since epoch.
  final refreshed = CvField<int>('refreshed');

  @override
  CvFields get fields => [name, kind, refreshed];
}

/// A git repository, the key is the canonical path of its top folder.
class DbDartProjectGit extends ScvStringRecordBase {
  /// The url of its remote, null when none.
  final remote = CvField<String>('remote');

  /// When the folder was read from the disk, in milliseconds since epoch.
  final refreshed = CvField<int>('refreshed');

  @override
  CvFields get fields => [remote, refreshed];
}

/// A folder scanned for dart projects, the key is its canonical path.
class DbDartProjectFolder extends ScvStringRecordBase {
  /// When the folder was scanned, in milliseconds since epoch.
  final refreshed = CvField<int>('refreshed');

  @override
  CvFields get fields => [refreshed];
}

/// The dart projects and local workspaces, the key is the canonical path of
/// their folder.
///
/// The keys are sorted by path: the projects below a folder are a key range
/// (see [dartProjectCacheWithinBoundaries]).
///
/// Named `project` in version 1 (dart projects only), the new name drops the
/// legacy records on upgrade: everything is scanned again.
final dartProjectStore = scvStringStoreFactory.store<DbDartProject>('entry');

/// The git repositories, the key is the canonical path of their top folder.
final dartProjectGitStore = scvStringStoreFactory.store<DbDartProjectGit>(
  'git',
);

/// The folders scanned, the key is their canonical path.
///
/// Named `folder` in version 1, see [dartProjectStore].
final dartProjectFolderStore = scvStringStoreFactory.store<DbDartProjectFolder>(
  'scan',
);

/// Dart project cache database schema.
final dartProjectCacheSchema = SdbDatabaseSchema(
  stores: [
    dartProjectStore.schema(),
    dartProjectGitStore.schema(),
    dartProjectFolderStore.schema(),
  ],
);

/// Current dart project cache database version.
///
/// Bumped to 2 when the local workspaces and the git repositories were
/// added: the version 1 stores are dropped, the folders are scanned again.
const dartProjectCacheVersion = 2;

/// Register the cv constructors of the cache models.
void initCvDartProjectCache() {
  cvAddConstructors([
    DbDartProject.new,
    DbDartProjectGit.new,
    DbDartProjectFolder.new,
  ]);
}

/// The key boundaries of everything strictly below the folder [path].
///
/// [separator] is the path separator: every key starting with
/// `<path><separator>` is in between (`/a/b/` included, `/a/b0` excluded for
/// `/a/b`).
SdbBoundaries<String> dartProjectCacheWithinBoundaries(
  String path, {
  required String separator,
}) {
  var prefix = path.endsWith(separator) ? path : '$path$separator';
  var upper =
      prefix.substring(0, prefix.length - 1) +
      String.fromCharCode(prefix.codeUnitAt(prefix.length - 1) + 1);
  return SdbBoundaries.values(prefix, upper);
}

/// The record of [project].
DbDartProject dbDartProjectFrom(DartProjectInfo project) => DbDartProject()
  ..name.v = project.name
  ..kind.v = project.kind.name
  ..refreshed.v = project.refreshed.millisecondsSinceEpoch;

/// Convert the records to their plain counterparts.
extension DbDartProjectExt on DbDartProject {
  /// The project of this record.
  DartProjectInfo toInfo() => DartProjectInfo(
    path: id,
    name: name.v ?? '',
    kind: dartProjectKindFromName(kind.v) ?? DartProjectKind.dart,
    refreshed: DateTime.fromMillisecondsSinceEpoch(refreshed.v ?? 0),
  );
}

/// The record of [git].
DbDartProjectGit dbDartProjectGitFrom(DartProjectGitFolderInfo git) =>
    DbDartProjectGit()
      ..remote.v = git.remote
      ..refreshed.v = git.refreshed.millisecondsSinceEpoch;

/// Convert the records to their plain counterparts.
extension DbDartProjectGitExt on DbDartProjectGit {
  /// The git folder of this record.
  DartProjectGitFolderInfo toInfo() => DartProjectGitFolderInfo(
    path: id,
    remote: remote.v,
    refreshed: DateTime.fromMillisecondsSinceEpoch(refreshed.v ?? 0),
  );
}

/// Convert the records to their plain counterparts.
extension DbDartProjectFolderExt on DbDartProjectFolder {
  /// The folder of this record.
  DartProjectFolderInfo toInfo() => DartProjectFolderInfo(
    path: id,
    refreshed: DateTime.fromMillisecondsSinceEpoch(refreshed.v ?? 0),
  );
}
