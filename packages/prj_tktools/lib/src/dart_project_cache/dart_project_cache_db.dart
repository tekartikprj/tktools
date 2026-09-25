import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';

import 'dart_project.dart';

/// A dart project, the key is the canonical path of its folder.
class DbDartProject extends ScvStringRecordBase {
  /// Package name.
  final name = CvField<String>('name');

  /// A [DartProjectKind] name.
  final kind = CvField<String>('kind');

  /// When the project was read from the disk, in milliseconds since epoch.
  final refreshed = CvField<int>('refreshed');

  @override
  CvFields get fields => [name, kind, refreshed];
}

/// A folder scanned for dart projects, the key is its canonical path.
class DbDartProjectFolder extends ScvStringRecordBase {
  /// When the folder was scanned, in milliseconds since epoch.
  final refreshed = CvField<int>('refreshed');

  @override
  CvFields get fields => [refreshed];
}

/// The dart projects, the key is the canonical path of their folder.
///
/// The keys are sorted by path: the projects below a folder are a key range
/// (see [dartProjectCacheWithinBoundaries]).
final dartProjectStore = scvStringStoreFactory.store<DbDartProject>('project');

/// The folders scanned, the key is their canonical path.
final dartProjectFolderStore = scvStringStoreFactory.store<DbDartProjectFolder>(
  'folder',
);

/// Dart project cache database schema.
final dartProjectCacheSchema = SdbDatabaseSchema(
  stores: [dartProjectStore.schema(), dartProjectFolderStore.schema()],
);

/// Current dart project cache database version.
const dartProjectCacheVersion = 1;

/// Register the cv constructors of the cache models.
void initCvDartProjectCache() {
  cvAddConstructors([DbDartProject.new, DbDartProjectFolder.new]);
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

/// Convert the records to their plain counterparts.
extension DbDartProjectFolderExt on DbDartProjectFolder {
  /// The folder of this record.
  DartProjectFolderInfo toInfo() => DartProjectFolderInfo(
    path: id,
    refreshed: DateTime.fromMillisecondsSinceEpoch(refreshed.v ?? 0),
  );
}
