import 'package:fs_shim/fs_shim.dart';

/// What a folder of the cache is: a dart project (the kind drives whether
/// `dart` or `flutter` runs its commands) or a local workspace.
enum DartProjectKind {
  /// A dart package.
  dart,

  /// A flutter package (a `flutter` sdk dependency).
  flutter,

  /// A pub workspace root holding dart packages only.
  dartWorkspace,

  /// A pub workspace root holding at least one flutter package, `flutter`
  /// runs its commands.
  flutterWorkspace,

  /// A local workspace: a folder with a `local_workspace.json` file, linking
  /// projects of several repositories. Not a dart project itself (it wins
  /// over a `pubspec.yaml` in the same folder).
  localWorkspace,
}

/// Helpers on [DartProjectKind].
extension DartProjectKindExt on DartProjectKind {
  /// True for a dart project (a `pubspec.yaml`), false for a local
  /// workspace.
  bool get isDart => this != DartProjectKind.localWorkspace;

  /// True for a local workspace.
  bool get isLocalWorkspace => this == DartProjectKind.localWorkspace;

  /// True when `flutter` (and not `dart`) runs the commands of the project.
  bool get isFlutter =>
      this == DartProjectKind.flutter ||
      this == DartProjectKind.flutterWorkspace;

  /// True for a pub workspace root.
  bool get isWorkspace =>
      this == DartProjectKind.dartWorkspace ||
      this == DartProjectKind.flutterWorkspace;

  /// Short label, displayed as a badge.
  String get label => switch (this) {
    DartProjectKind.dart => 'dart',
    DartProjectKind.flutter => 'flutter',
    DartProjectKind.dartWorkspace => 'dart workspace',
    DartProjectKind.flutterWorkspace => 'flutter workspace',
    DartProjectKind.localWorkspace => 'local workspace',
  };
}

/// The kind named [name] (see [Enum.name]), null when unknown.
DartProjectKind? dartProjectKindFromName(String? name) {
  for (var kind in DartProjectKind.values) {
    if (kind.name == name) {
      return kind;
    }
  }
  return null;
}

/// The kind of a project, from what its `pubspec.yaml` says.
///
/// [isFlutter] for a workspace root is true when one of its packages is a
/// flutter one.
DartProjectKind dartProjectKindOf({
  required bool isFlutter,
  required bool isWorkspace,
}) => isWorkspace
    ? (isFlutter
          ? DartProjectKind.flutterWorkspace
          : DartProjectKind.dartWorkspace)
    : (isFlutter ? DartProjectKind.flutter : DartProjectKind.dart);

/// Canonical absolute path of [path] on [fs], the key of the cache.
String dartProjectCanonicalPath(FileSystem fs, String path) =>
    fs.path.canonicalize(fs.path.absolute(path));

/// A dart project (or a local workspace) of the cache.
class DartProjectInfo {
  /// Canonical absolute path of the project folder, the key of the cache.
  final String path;

  /// Package name, the folder name when the `pubspec.yaml` has none (or for
  /// a local workspace).
  final String name;

  /// What the project is.
  final DartProjectKind kind;

  /// When the project was read from the disk.
  final DateTime refreshed;

  /// Creates a project.
  const DartProjectInfo({
    required this.path,
    required this.name,
    required this.kind,
    required this.refreshed,
  });

  /// The same project, with another [kind].
  DartProjectInfo copyWith({DartProjectKind? kind}) => DartProjectInfo(
    path: path,
    name: name,
    kind: kind ?? this.kind,
    refreshed: refreshed,
  );

  @override
  String toString() => '$name ($path, ${kind.label})';
}

/// A folder of the cache, it was scanned for dart projects.
///
/// Everything below it is in the cache: displaying one of its sub folders
/// needs no scan.
class DartProjectFolderInfo {
  /// Canonical absolute path of the folder.
  final String path;

  /// When the folder was scanned.
  final DateTime refreshed;

  /// Creates a folder.
  const DartProjectFolderInfo({required this.path, required this.refreshed});

  @override
  String toString() => '$path ($refreshed)';
}

/// A git repository of the cache: a folder with a `.git` entry.
class DartProjectGitFolderInfo {
  /// Canonical absolute path of the repository (its top folder).
  final String path;

  /// The url of its `origin` remote (the first one when none is named
  /// `origin`), null when it has none (or it could not be read).
  final String? remote;

  /// When the folder was read from the disk.
  final DateTime refreshed;

  /// Creates a git folder.
  const DartProjectGitFolderInfo({
    required this.path,
    required this.remote,
    required this.refreshed,
  });

  @override
  String toString() => '$path (git ${remote ?? 'no remote'})';
}
