import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'dart_run_entry.dart';

/// The packages of the Flutter SDK (`flutter`, `flutter_test`,
/// `integration_test`...): importing one needs `flutter run` or
/// `flutter test`.
const flutterSdkPackageNames = {
  'flutter',
  'flutter_driver',
  'flutter_goldens',
  'flutter_localizations',
  'flutter_test',
  'flutter_web_plugins',
  'fuchsia_remote_debug_protocol',
  'integration_test',
  'sky_engine',
};

/// The `dart.library.<name>` that are true on the Dart VM (`dart run`,
/// `dart test`), the ones a conditional import picks there.
const dartVmLibraries = {
  'async',
  'cli',
  'collection',
  'concurrent',
  'convert',
  'core',
  'developer',
  'ffi',
  'io',
  'isolate',
  'math',
  'mirrors',
  'nativewrappers',
  'typed_data',
};

/// An import, export or part, its default uri then its `if (...) 'uri'`
/// configurations.
final _directiveRegExp = RegExp(
  r'''^\s*(?:import|export|part)\s+(?!of\b)((?:'[^']*'|"[^"]*")(?:\s+if\s*\([^)]*\)\s*(?:'[^']*'|"[^"]*"))*)''',
  multiLine: true,
);
final _configurationRegExp = RegExp(
  r'''if\s*\(([^)]*)\)\s*(?:'([^']*)'|"([^"]*)")''',
);
final _firstStringRegExp = RegExp(r'''^(?:'([^']*)'|"([^"]*)")''');
final _conditionRegExp = RegExp(
  r'''^dart\.library\.(\w+)(?:\s*==\s*(?:'true'|"true"))?$''',
);
final _pubspecNameRegExp = RegExp(r'^name:\s*(\S+)', multiLine: true);

/// The uris of the imports, exports and parts of [source], the one the Dart
/// VM compiles for a conditional import (the first configuration true on the
/// VM, see [dartVmLibraries], else the default one).
List<String> dartSourceVmDirectiveUris(String source) {
  var uris = <String>[];
  for (var match in _directiveRegExp.allMatches(
    dartSourceWithoutComments(source),
  )) {
    var text = match.group(1)!;
    var first = _firstStringRegExp.firstMatch(text)!;
    var uri = first.group(1) ?? first.group(2)!;
    for (var configuration in _configurationRegExp.allMatches(text)) {
      var condition = _conditionRegExp.firstMatch(
        configuration.group(1)!.trim(),
      );
      if (condition != null && dartVmLibraries.contains(condition.group(1))) {
        uri = configuration.group(2) ?? configuration.group(3)!;
        break;
      }
    }
    uris.add(uri);
  }
  return uris;
}

/// Tells whether the dart files of a project need Flutter (`flutter run`,
/// `flutter test`) or run on the Dart VM (`dart run`, `dart test`).
///
/// The imports, exports and parts are followed from a file (`package:` uris
/// through the package config of the project, `.dart_tool/package_config.json`
/// in it or in its pub workspace) until a Flutter SDK library is found:
/// `dart:ui` or a library of [flutterSdkPackageNames]. What is read is kept:
/// scan all the entries of a project with the same scanner.
class DartImportScanner {
  /// The project the files belong to.
  final String projectPath;

  /// The lib folder of each package, null until read.
  Map<String, String>? _packageLibDirs;

  /// The packages of the Flutter SDK found in the package config.
  final _flutterPackages = <String>{...flutterSdkPackageNames};

  /// The directive uris of the files read.
  final _fileUris = <String, List<String>>{};

  /// Files whose whole import tree was read without finding Flutter.
  final _vmOnlyFiles = <String>{};

  /// Creates a scanner for the project at [projectPath].
  DartImportScanner(String projectPath)
    : projectPath = p.normalize(p.absolute(projectPath));

  /// True when [filePath] imports, directly or not, a Flutter SDK library.
  Future<bool> requiresFlutter(String filePath) async =>
      (await flutterImportChain(filePath)) != null;

  /// True when one of [filePaths] needs Flutter.
  Future<bool> anyRequiresFlutter(Iterable<String> filePaths) async {
    for (var filePath in filePaths) {
      if (await requiresFlutter(filePath)) {
        return true;
      }
    }
    return false;
  }

  /// How [filePath] reaches Flutter: the files from [filePath] (relative to
  /// the project, or a `package:` uri) to the Flutter uri imported
  /// (`package:flutter/material.dart`), null when it does not.
  Future<List<String>?> flutterImportChain(String filePath) async {
    var start = p.normalize(p.absolute(projectPath, filePath));
    if (_vmOnlyFiles.contains(start)) {
      return null;
    }
    _packageLibDirs ??= await _readPackageLibDirs();
    var parents = <String, String?>{start: null};
    var queue = Queue<String>()..add(start);
    while (queue.isNotEmpty) {
      var file = queue.removeFirst();
      if (_vmOnlyFiles.contains(file)) {
        continue;
      }
      for (var uri in await _uris(file)) {
        if (_isFlutterUri(uri)) {
          var chain = <String>[uri];
          String? current = file;
          while (current != null) {
            chain.add(_display(current));
            current = parents[current];
          }
          return chain.reversed.toList();
        }
        var target = _resolve(uri, from: file);
        if (target != null && !parents.containsKey(target)) {
          parents[target] = file;
          queue.add(target);
        }
      }
    }
    _vmOnlyFiles.addAll(parents.keys);
    return null;
  }

  Future<List<String>> _uris(String file) async {
    var uris = _fileUris[file];
    if (uris == null) {
      try {
        uris = dartSourceVmDirectiveUris(await File(file).readAsString());
      } catch (_) {
        // Missing (a generated file not generated yet), unreadable.
        uris = const [];
      }
      _fileUris[file] = uris;
    }
    return uris;
  }

  bool _isFlutterUri(String uri) {
    if (uri == 'dart:ui' || uri == 'dart:ui_web') {
      return true;
    }
    if (uri.startsWith('package:')) {
      var name = uri.substring('package:'.length).split('/').first;
      return _flutterPackages.contains(name);
    }
    return false;
  }

  /// The file [uri] points to from [from], null for a `dart:` library or an
  /// unknown package.
  String? _resolve(String uri, {required String from}) {
    if (uri.startsWith('dart:')) {
      return null;
    }
    if (uri.startsWith('package:')) {
      var path = uri.substring('package:'.length);
      var slash = path.indexOf('/');
      if (slash < 0) {
        return null;
      }
      var libDir = _packageLibDirs![path.substring(0, slash)];
      if (libDir == null) {
        return null;
      }
      return p.normalize(p.join(libDir, path.substring(slash + 1)));
    }
    var parsed = Uri.tryParse(uri);
    if (parsed == null || parsed.hasScheme) {
      return null;
    }
    return p.normalize(
      p.join(p.dirname(from), p.joinAll(p.posix.split(parsed.path))),
    );
  }

  /// [file] relative to the project, or as a `package:` uri.
  String _display(String file) {
    if (p.isWithin(projectPath, file)) {
      return p.posix.joinAll(p.split(p.relative(file, from: projectPath)));
    }
    for (var entry in _packageLibDirs!.entries) {
      if (p.isWithin(entry.value, file)) {
        var path = p.posix.joinAll(
          p.split(p.relative(file, from: entry.value)),
        );
        return 'package:${entry.key}/$path';
      }
    }
    return file;
  }

  /// The lib folders of the packages of the package config, the project
  /// itself only (from its `pubspec.yaml`) when there is none (no pub get).
  ///
  /// The package config is the one of the project, or the one of a parent
  /// folder listing the project (a pub workspace member).
  Future<Map<String, String>> _readPackageLibDirs() async {
    var dir = projectPath;
    while (true) {
      var file = File(p.join(dir, '.dart_tool', 'package_config.json'));
      if (file.existsSync()) {
        var libDirs = await _readPackageConfig(file);
        if (libDirs != null &&
            (dir == projectPath || libDirs.values.any(_isProjectLibDir))) {
          return libDirs;
        }
      }
      var parent = p.dirname(dir);
      if (parent == dir) {
        break;
      }
      dir = parent;
    }
    try {
      var pubspec = await File(
        p.join(projectPath, 'pubspec.yaml'),
      ).readAsString();
      var name = _pubspecNameRegExp.firstMatch(pubspec)?.group(1);
      if (name != null) {
        return {name: p.join(projectPath, 'lib')};
      }
    } catch (_) {
      // No pubspec.
    }
    return {};
  }

  bool _isProjectLibDir(String libDir) =>
      p.equals(libDir, p.join(projectPath, 'lib'));

  /// The lib folder of each package of [configFile], null when unreadable.
  Future<Map<String, String>?> _readPackageConfig(File configFile) async {
    try {
      var config =
          jsonDecode(await configFile.readAsString()) as Map<String, Object?>;
      var configUri = p.toUri(configFile.absolute.path);
      var libDirs = <String, String>{};
      String? flutterSdkPackagesDir;
      for (var package in (config['packages'] as List).cast<Map>()) {
        var name = package['name'] as String;
        var rootUri = configUri.resolve(_dirUri(package['rootUri'] as String));
        var packageUri = package['packageUri'] as String? ?? 'lib/';
        libDirs[name] = p.normalize(
          p.fromUri(rootUri.resolve(_dirUri(packageUri))),
        );
        if (name == 'flutter') {
          flutterSdkPackagesDir = p.dirname(p.fromUri(rootUri));
        }
      }
      // Every package of the Flutter SDK, the ones not listed too.
      if (flutterSdkPackagesDir != null) {
        for (var entry in libDirs.entries) {
          if (p.isWithin(flutterSdkPackagesDir, entry.value)) {
            _flutterPackages.add(entry.key);
          }
        }
      }
      return libDirs;
    } catch (_) {
      return null;
    }
  }
}

String _dirUri(String uri) => uri.endsWith('/') ? uri : '$uri/';
