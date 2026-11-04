import 'dart:io';

import 'package:path/path.dart' as p;

/// The folders of a project holding something to run or to test, in display
/// order.
enum DartRunFolder {
  /// `lib/`: the files with `main` in their name declaring a top-level
  /// `main` (`lib/main.dart`, `lib/main_web.dart`, `lib/test_main.dart`).
  lib('lib'),

  /// `example/` when it is not a project of its own: the files declaring a
  /// top-level `main`.
  example('example'),

  /// `bin/`: the scripts.
  bin('bin'),

  /// `tool/`: the scripts.
  tool('tool'),

  /// `test/`: the `_test.dart` files and the folders holding them.
  test('test'),

  /// `integration_test/`: the tests run in an app on a device.
  integrationTest('integration_test');

  /// The folder, relative to the project.
  final String path;

  const DartRunFolder(this.path);

  /// True for the test folders.
  bool get isTest => this == test || this == integrationTest;
}

/// Something to run or to test in a project.
class DartRunEntry {
  /// Path relative to the project, posix style (`lib/main.dart`, `test`,
  /// `test/src`).
  final String path;

  /// The folder holding it.
  final DartRunFolder folder;

  /// True for a folder of tests.
  final bool isDirectory;

  /// Creates an entry.
  const DartRunEntry({
    required this.path,
    required this.folder,
    this.isDirectory = false,
  });

  /// True for a test file or a folder of tests.
  bool get isTest => folder.isTest;

  @override
  String toString() => isDirectory ? '$path/' : path;

  @override
  int get hashCode => path.hashCode;

  @override
  bool operator ==(Object other) =>
      other is DartRunEntry &&
      other.path == path &&
      other.folder == folder &&
      other.isDirectory == isDirectory;
}

/// The entry of [relativePath] (posix, relative to the project), even when
/// [findDartRunEntries] does not list it: its folder from its first segment
/// (a test when in test/ or integration_test/ or a `_test.dart` file).
DartRunEntry dartRunEntryFromPath(
  String relativePath, {
  bool isDirectory = false,
}) {
  var first = p.posix.split(relativePath).first;
  var folder =
      DartRunFolder.values
          .where((folder) => folder.path == first)
          .firstOrNull ??
      (relativePath.endsWith('_test.dart')
          ? DartRunFolder.test
          : DartRunFolder.tool);
  return DartRunEntry(
    path: relativePath,
    folder: folder,
    isDirectory: isDirectory,
  );
}

/// The `_test.dart` files below the folder [dirPath] (hidden folders,
/// `build/` and nested projects skipped).
List<String> findDartTestFiles(String dirPath) => _dartFiles(
  Directory(dirPath),
).where((file) => file.endsWith('_test.dart')).toList();

/// The project holding [path] (a file or a folder): the closest folder with
/// a `pubspec.yaml`, null when none.
String? dartRunProjectRoot(String path) {
  var dir = p.normalize(p.absolute(path));
  if (!Directory(dir).existsSync()) {
    dir = p.dirname(dir);
  }
  while (true) {
    if (File(p.join(dir, 'pubspec.yaml')).existsSync()) {
      return dir;
    }
    var parent = p.dirname(dir);
    if (parent == dir) {
      return null;
    }
    dir = parent;
  }
}

final _blockCommentRegExp = RegExp(r'/\*.*?\*/', dotAll: true);
final _lineCommentRegExp = RegExp(r'//.*$', multiLine: true);

/// [source] without its comments (good enough to read the directives and the
/// top-level declarations, a `//` in a string cuts its line).
String dartSourceWithoutComments(String source) => source
    .replaceAll(_blockCommentRegExp, '')
    .replaceAll(_lineCommentRegExp, '');

/// A top-level `main` declaration: at the start of a line, its return type
/// first if any (`main(`, `void main(`, `Future<void> main(`).
final _mainRegExp = RegExp(
  r'^(?:[A-Za-z_][\w<>?, ]* )?main\s*\(',
  multiLine: true,
);

/// True when [source] declares a top-level `main` function.
bool dartSourceDeclaresMain(String source) =>
    _mainRegExp.hasMatch(dartSourceWithoutComments(source));

/// The things to run or to test in the project at [projectPath], in
/// [DartRunFolder] order, each folder sorted by path, a test folder before
/// what it holds.
///
/// Nested projects (a folder with a `pubspec.yaml`, an `example/` app),
/// hidden folders and `build/` are skipped.
Future<List<DartRunEntry>> findDartRunEntries(String projectPath) async {
  var entries = <DartRunEntry>[];
  for (var folder in DartRunFolder.values) {
    var dir = Directory(p.join(projectPath, folder.path));
    if (!dir.existsSync() ||
        File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
      continue;
    }
    var files = _dartFiles(dir).toList();
    var found = <DartRunEntry>[];
    if (folder.isTest) {
      var testFiles = files
          .where((file) => file.endsWith('_test.dart'))
          .toList();
      // The folders holding tests, the test folder itself included.
      var dirs = <String>{};
      for (var file in testFiles) {
        var parent = p.dirname(file);
        while (p.isWithin(dir.path, parent) || p.equals(dir.path, parent)) {
          dirs.add(parent);
          if (p.equals(dir.path, parent)) {
            break;
          }
          parent = p.dirname(parent);
        }
      }
      for (var path in dirs) {
        found.add(
          DartRunEntry(
            path: _relative(path, projectPath),
            folder: folder,
            isDirectory: true,
          ),
        );
      }
      for (var file in testFiles) {
        found.add(
          DartRunEntry(path: _relative(file, projectPath), folder: folder),
        );
      }
    } else {
      for (var file in files) {
        if (folder == DartRunFolder.lib && !p.basename(file).contains('main')) {
          continue;
        }
        String source;
        try {
          source = await File(file).readAsString();
        } catch (_) {
          continue;
        }
        if (dartSourceDeclaresMain(source)) {
          found.add(
            DartRunEntry(path: _relative(file, projectPath), folder: folder),
          );
        }
      }
    }
    // A folder before the files it holds: `test` < `test/a_test.dart`.
    found.sort((a, b) => a.path.compareTo(b.path));
    entries.addAll(found);
  }
  return entries;
}

String _relative(String path, String projectPath) =>
    p.posix.joinAll(p.split(p.relative(path, from: projectPath)));

/// The dart files below [dir], not following links, skipping hidden folders,
/// `build/` and nested projects.
Iterable<String> _dartFiles(Directory dir) sync* {
  List<FileSystemEntity> children;
  try {
    children = dir.listSync(followLinks: false);
  } catch (_) {
    return;
  }
  for (var child in children) {
    var name = p.basename(child.path);
    if (child is File) {
      if (name.endsWith('.dart')) {
        yield child.path;
      }
    } else if (child is Directory) {
      if (name.startsWith('.') ||
          name == 'build' ||
          File(p.join(child.path, 'pubspec.yaml')).existsSync()) {
        continue;
      }
      yield* _dartFiles(child);
    }
  }
}
