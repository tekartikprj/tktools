import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_git.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_model.dart';

/// The checkouts folder in the temp folder of the machine (cleared at reboot
/// on most systems: a run clones its repository again).
String get hostCiTempCheckoutsDir =>
    p.join(Directory.systemTemp.path, 'tekartik_host_ci_checkouts');

/// A checkout cloned by Host CI (see `HostCi.getCheckouts`).
class HostCiCheckout {
  /// The clone folder.
  final String path;

  /// Its name: the path in the checkouts folder (`github.com/dart-lang/core`),
  /// [path] when outside.
  final String name;

  /// False when cleared (the next full run of its projects clones it again).
  final bool exists;

  /// Its size in bytes, null when not computed or not there.
  final int? size;

  /// The projects using it, empty for a clone left by no project.
  final List<DbHostCiProject> projects;

  /// Creates a checkout.
  const HostCiCheckout({
    required this.path,
    required this.name,
    required this.exists,
    required this.size,
    required this.projects,
  });

  @override
  String toString() =>
      '$name${size == null ? '' : ' ${hostCiFormatSize(size!)}'}'
      ' (${projects.length} projects)';
}

/// The git checkouts below [dir] (a checkout is not searched inside), sorted;
/// empty when [dir] does not exist.
Future<List<String>> hostCiFindGitCheckouts(
  String dir, {
  int maxDepth = 6,
}) async {
  var found = <String>[];
  Future<void> visit(Directory current, int depth) async {
    if (hostCiIsGitCheckout(current.path)) {
      found.add(current.path);
      return;
    }
    if (depth >= maxDepth) {
      return;
    }
    List<FileSystemEntity> entities;
    try {
      entities = await current.list(followLinks: false).toList();
    } catch (_) {
      return;
    }
    for (var entity in entities) {
      if (entity is Directory) {
        await visit(entity, depth + 1);
      }
    }
  }

  var root = Directory(dir);
  if (root.existsSync()) {
    await visit(root, 0);
  }
  found.sort();
  return found;
}

/// The size of the files below [path] in bytes (links not followed), null
/// when [path] does not exist.
Future<int?> hostCiDirSize(String path) async {
  var dir = Directory(path);
  if (!dir.existsSync()) {
    return null;
  }
  var size = 0;
  try {
    await for (var entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          size += await entity.length();
        } catch (_) {}
      }
    }
  } catch (_) {
    // What could be read.
  }
  return size;
}

/// A size for humans: `512 B`, `12.3 KB`, `4.5 MB`, `1.2 GB`.
String hostCiFormatSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0
      ? '$bytes B'
      : '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}
