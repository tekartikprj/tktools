import 'dart:io';

import 'package:dev_build/build_support.dart';
import 'package:path/path.dart' as p;
import 'package:process_run/shell.dart';

import 'dart_run_command.dart';
import 'dart_run_device.dart';
import 'dart_run_entry.dart';

/// The platforms of `flutter create --platforms`, each one a folder of a
/// Flutter project.
const flutterProjectPlatforms = [
  'android',
  'ios',
  'linux',
  'macos',
  'windows',
  'web',
];

/// The platform folder of a Flutter app run on a device of [targetPlatform]
/// (`android-arm64`, `ios`, `darwin`, `linux-x64`, `windows-x64`,
/// `web-javascript`), or on the device [id] when its platform is unknown
/// (`linux`, `macos`, `windows`, `chrome`, `emulator-5554`); null when
/// unknown.
String? flutterPlatformOfDevice({
  required String id,
  required String targetPlatform,
}) {
  if (targetPlatform.isNotEmpty) {
    if (targetPlatform.startsWith('android')) {
      return 'android';
    } else if (targetPlatform == 'ios') {
      return 'ios';
    } else if (targetPlatform == 'darwin') {
      return 'macos';
    } else if (targetPlatform.startsWith('linux')) {
      return 'linux';
    } else if (targetPlatform.startsWith('windows')) {
      return 'windows';
    } else if (targetPlatform.startsWith('web')) {
      return 'web';
    }
    return null;
  }
  return switch (id) {
    'linux' || 'macos' || 'windows' => id,
    'chrome' || 'edge' || 'web-server' => 'web',
    _ => id.startsWith('emulator-') ? 'android' : null,
  };
}

/// The platform folder of the project (see `flutter create --platforms`)
/// that the command of [entry] on [target] needs (see [dartRunCommandLine]),
/// null when none:
/// - a Flutter run: this computer's platform ([hostOs], `linux`, `macos` or
///   `windows`) on the VM, `web` in a browser, the device's platform;
/// - integration tests on a device: the device's platform (see
///   [dartTestFlutterPlatform]);
/// - none for a Dart run and for the other tests.
String? dartRunFlutterPlatform(
  DartRunEntry entry, {
  required DartRunTarget target,
  required bool flutter,
  String? hostOs,
}) {
  if (entry.isTest) {
    return dartTestFlutterPlatform([entry.path], target: target);
  }
  return switch (target.kind) {
    DartRunTargetKind.vm => flutter ? hostOs ?? dartRunHostOs() : null,
    DartRunTargetKind.chrome ||
    DartRunTargetKind.node ||
    DartRunTargetKind.firefox => 'web',
    DartRunTargetKind.device => _targetDevicePlatform(target),
  };
}

/// The platform folder of the project that testing [paths] (relative to the
/// project) on [target] needs (see [dartTestCommandLine]): the device's
/// platform for integration tests (a path in `integration_test/`, that
/// `flutter test -d` runs in an app on the device), null otherwise.
String? dartTestFlutterPlatform(
  List<String> paths, {
  required DartRunTarget target,
}) {
  if (target.kind != DartRunTargetKind.device ||
      !paths.any((path) => p.split(path).first == 'integration_test')) {
    return null;
  }
  return _targetDevicePlatform(target);
}

String? _targetDevicePlatform(DartRunTarget target) {
  var device = target.device;
  return device == null
      ? null
      : flutterPlatformOfDevice(
          id: device.id,
          targetPlatform: device.targetPlatform,
        );
}

/// The platforms of [flutterProjectPlatforms] that the project at
/// [projectPath] has (its `android/`, `ios/`... folders).
List<String> flutterProjectExistingPlatforms(String projectPath) => [
  for (var platform in flutterProjectPlatforms)
    if (Directory(p.join(projectPath, platform)).existsSync()) platform,
];

/// The `flutter create` command line, run in a project, creating its
/// [platforms] folders: `flutter create [--template <template>] --platforms
/// linux,web --no-pub [--project-name <name>] .`.
///
/// [projectName] (the pubspec name) gives the app its name (the Linux
/// binary, the Android package), the folder name otherwise.
String flutterCreatePlatformsCommandLine(
  List<String> platforms, {
  String? projectName,
  String? template,
}) => [
  'flutter',
  'create',
  if (template != null) ...['--template', shellArgument(template)],
  '--platforms',
  shellArgument(platforms.join(',')),
  '--no-pub',
  if (projectName != null) ...['--project-name', shellArgument(projectName)],
  '.',
].join(' ');

/// Folders [flutterCreatePlatforms] never looks into.
const _createIgnoredDirs = {'.dart_tool', 'build', '.git'};

/// Creates the missing [platforms] folders of the Flutter project at
/// [projectPath] (`flutter create --platforms`, see
/// [flutterCreatePlatformsCommandLine]) and only them: everything else
/// `flutter create` adds to an existing project (`lib/main.dart`,
/// `test/widget_test.dart`, `.metadata`, `.gitignore`, `README.md`,
/// `analysis_options.yaml`, `pubspec.lock`, `.idea/`, `<name>.iml`) is
/// deleted.
///
/// Returns the platforms created, empty when none was missing. [shell] runs
/// `flutter create` (verbose by default) in [projectPath], whatever its
/// working directory; [template] is passed to `flutter create`.
Future<List<String>> flutterCreatePlatforms(
  String projectPath,
  List<String> platforms, {
  Shell? shell,
  String? template,
}) async {
  var existing = flutterProjectExistingPlatforms(projectPath);
  var missing = platforms
      .where((platform) => !existing.contains(platform))
      .toSet()
      .toList();
  if (missing.isEmpty) {
    return missing;
  }
  var before = _createWatchedPaths(projectPath);
  var pubspec = await pathGetPubspecYamlMap(projectPath);
  // Absolute: cd of a relative path is relative to the shell's folder.
  shell = (shell ?? Shell()).cd(p.absolute(projectPath));
  await shell.run(
    flutterCreatePlatformsCommandLine(
      missing,
      projectName: pubspecYamlGetPackageName(pubspec),
      template: template,
    ),
  );
  var created = _createWatchedPaths(
    projectPath,
  ).where((path) => !before.contains(path)).toList();
  // Files first, then the folders, deepest first.
  created.sort((a, b) => b.length.compareTo(a.length));
  for (var path in created) {
    var absolute = p.join(projectPath, path);
    if (FileSystemEntity.isDirectorySync(absolute)) {
      var dir = Directory(absolute);
      if (dir.existsSync() && dir.listSync().isEmpty) {
        dir.deleteSync();
      }
    } else {
      File(absolute).deleteSync();
    }
  }
  return missing;
}

/// The files and folders of the project at [projectPath] (relative paths)
/// that `flutter create` may add, outside its platform folders.
Set<String> _createWatchedPaths(String projectPath) {
  var paths = <String>{};
  void list(Directory dir, {required bool top}) {
    for (var entity in dir.listSync(followLinks: false)) {
      var path = p.relative(entity.path, from: projectPath);
      if (entity is Directory) {
        var name = p.basename(path);
        if (top &&
            (flutterProjectPlatforms.contains(name) ||
                _createIgnoredDirs.contains(name))) {
          continue;
        }
        paths.add(path);
        list(entity, top: false);
      } else {
        paths.add(path);
      }
    }
  }

  list(Directory(projectPath), top: true);
  return paths;
}
