import 'package:args/args.dart';
import 'package:cv/cv.dart';
import 'package:fs_shim/utils/io/read_write.dart' show linesToIoString;
import 'package:fs_shim/utils/path.dart' show toPosixPath;
import 'package:path/path.dart';
import 'package:process_run/shell.dart';
import 'package:process_run/stdio.dart';
// ignore: implementation_imports
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub_package_info.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:tekartik_prj_tktools/tkpub.dart';
import 'package:tekartik_sc/git.dart';
import 'package:yaml/yaml.dart';

import '../utils.dart';

/// Dev flag
const flagDevKey = 'dev';

/// Force flag
const flagForceKey = 'force';

/// Overrides flag
const flagOverridesKey = 'overrides';

/// pub spec overrides
const flagPubspecOverridesKey = 'pubspec-overrides';

/// Recursive
const flagRecursiveKey = 'recursive';

/// Read config instead of filtering by dependencies
const flagReadConfigKey = 'read-config';

/// Clear
class TkPubClearCommand extends TkPubAddRemoveCommand {
  @override
  bool get isClear => true;

  /// Clear
  TkPubClearCommand()
      : super(name: 'clear', parser: ArgParser(allowTrailingOptions: true)) {
    parser.addFlag(flagPubspecOverridesKey,
        help: 'Clear pubspec_overrides.yaml');
    parser.addFlag(flagRecursiveKey,
        help: 'Go to every subfolder (pubspec-overrides only for now)');
  }
}

/// Pub remove.
class TkPubRemoveCommand extends TkPubAddRemoveCommand {
  @override
  bool get isRemove => true;

  /// Pub remove
  TkPubRemoveCommand()
      : super(name: 'remove', parser: ArgParser(allowTrailingOptions: true)) {
    parser.addFlag(flagDevKey, help: 'Remove from dev_dependencies mode');
    parser.addFlag(flagOverridesKey, help: 'Remove from dependecy_overrides');
    parser.addFlag(flagPubspecOverridesKey,
        help: 'Remove from pubspec_overrides.yaml');
    parser.addFlag(flagRecursiveKey,
        help: 'Go to every subfolder (pubspec-overrides only for now)');
  }
}

/// Pub add
class TkPubAddCommand extends TkPubAddRemoveCommand {
  @override
  bool get isAdd => true;

  /// Pub add
  TkPubAddCommand()
      : super(
            name: 'add',
            parser: ArgParser(allowTrailingOptions: true),
            description: '''
tkpub add [dev:|override:|pubspec_overrides:]package1 [package2]

Add package using user env config
      ''') {
    parser.addFlag(flagDevKey, abbr: 'd', help: 'Add to dev_dependencies mode');
    parser.addFlag(flagOverridesKey,
        abbr: 'o', help: 'Add to dependecy_overrides');
    parser.addFlag(flagForceKey,
        abbr: 'f', help: 'Force adding (hosted only or specified)');
    parser.addFlag(flagPubspecOverridesKey,
        abbr: 'p', help: 'Add to pubspec_overrides.yaml');
    parser.addFlag(flagRecursiveKey,
        abbr: 'r',
        help: 'Go to every subfolder (pubspec-overrides only for now)');
    parser.addFlag(flagReadConfigKey,
        abbr: 'c', help: 'Read config instead of filtering by dependencies');
  }
}

class _PackageToAdd {
  final String path;
  final String dartPubAddArg;

  _PackageToAdd(this.path, this.dartPubAddArg);
}

class _PackagesToAdd {
  final String path;
  final List<String> dartPubAddArgs;

  _PackagesToAdd(this.path, this.dartPubAddArgs);
}

class _PackageToAddList {
  final list = <_PackageToAdd>[];
  void add(String path, String dartPubAddArg) {
    list.add(_PackageToAdd(path, dartPubAddArg));
  }

  List<_PackagesToAdd> group() {
    var map = <String, List<String>>{};
    for (var packageToAdd in list) {
      var path = packageToAdd.path;
      var dartPubAddArg = packageToAdd.dartPubAddArg;
      var list = map.putIfAbsent(path, () => <String>[]);
      list.add(dartPubAddArg);
    }
    return map.entries.map((e) => _PackagesToAdd(e.key, e.value)).toList();
  }
}

/// Add/remove
abstract class TkPubAddRemoveCommand extends TkPubSubCommand {
  /// true if is add
  bool get isAdd => false;

  /// true is is remove
  bool get isRemove => false;

  /// true if is clear
  bool get isClear => false;

  /// Add/remove
  TkPubAddRemoveCommand({required super.name, super.parser, super.description});
  @override
  FutureOr<bool> onRun() async {
    var globalDev = !isClear ? results.flag(flagDevKey) : false;
    var globalOverrides = !isClear ? results.flag(flagOverridesKey) : false;
    var globalPubspecOverrides = results.flag(flagPubspecOverridesKey);
    var recursive = results.flag(flagRecursiveKey);
    var force = isAdd ? results.flag(flagForceKey) : false;
    var readConfig = results.flag(flagReadConfigKey);

    if (globalOverrides) {
      if (globalOverrides || globalOverrides) {
        throw ArgumentError(
            'Cannot use --$flagPubspecOverridesKey with --$flagDevKey or --$flagOverridesKey');
      }
    }

    var rest = results.rest;
    if (isClear && rest.isNotEmpty) {
      throw ArgumentError('No argument expected for clear');
    }
    if (!isClear && rest.isEmpty) {
      throw ArgumentError(
          'At least one argument expected (package name with optional target and dev)');
    }
    var verbose = this.verbose;

    if (verbose) {
      stdout.writeln('Current directory ${Directory.current}');
    }
    Future<void> handleTopPath(
        String path, Future<void> Function(String path) handlePath) async {
      if (recursive) {
        for (var subPath in await recursivePubPath([path])) {
          await handlePath(subPath);
        }
      } else {
        await handlePath(path);
      }
    }

    /// Direct or dev dependencies to add.
    final toAdd = _PackageToAddList();

    await dbAction((db) async {
      final topPath = '.';

      if (isClear) {
        if (globalPubspecOverrides) {
          Future<void> handlePath(String path) async {
            stdout.writeln('# ${relative(path, from: topPath)}');
            var pubspecOverrideFile =
                File(join(path, 'pubspec_overrides.yaml'));
            if (pubspecOverrideFile.existsSync()) {
              await pubspecOverrideFile.delete();
              stdout.writeln('Removed pubspec_overrides.yaml');
            }
          }

          await handleTopPath(topPath, handlePath);
        } else {
          stderr.writeln('Must specify --pubspec-overrides');
        }
      } else {
        for (var arg in rest) {
          var info = TkpubPackageInfo.parse(arg);
          var packageName = info.name;
          // True for add only!
          //var packageHasDefinition = packageName != packageNameOrDef;
          var package =
              await db.getPackageOrNull(packageName, addMissingRef: true);

          var pubspecOverrides = info.target == TkPubTarget.pubspecOverrides ||
              (info.target == null && globalPubspecOverrides);

          if (pubspecOverrides) {
            var dependencies = [packageName];

            /// Find all local project in git
            var gitTopLevelPath = await findGitTopLevelPath(topPath);
            var allPackageWithDependency = <String>{};
            if (gitTopLevelPath != null) {
              var pathsHandled = <String>{};
              while (true) {
                List<String> allPaths;
                if (readConfig) {
                  allPaths = <String>[];
                  var allPksPaths = await recursivePubPath(
                    [gitTopLevelPath],
                  );
                  for (var pkgPath in allPksPaths.toList()) {
                    var pubspecYaml = await pathGetPubspecYamlMap(pkgPath);
                    if (pubspecYamlHasAnyDependencies(
                        pubspecYaml, dependencies)) {
                      if (verbose) {
                        stdout.writeln(
                            '$pkgPath has any dependencies in $dependencies');
                      }
                      allPaths.add(pkgPath);
                    } else {
                      if (verbose) {
                        stdout.writeln(
                            '$pkgPath does not have any dependencies in $dependencies, checking package-config.yaml');
                      }

                      Model? packageConfigMap;
                      try {
                        packageConfigMap =
                            await pathGetPackageConfigMap(pkgPath);
                      } catch (_) {
                        try {
                          await Shell(workingDirectory: pkgPath).run('pub get');

                          packageConfigMap =
                              await pathGetPubspecYamlMap(pkgPath);
                        } catch (e) {
                          stderr.writeln(
                              'Error: $e failed to get package-config.yaml');
                        }
                      }
                      if (packageConfigMap != null) {
                        if (packageConfigGetPackages(packageConfigMap)
                            .toSet()
                            .intersection(dependencies.toSet())
                            .isNotEmpty) {
                          if (verbose) {
                            stdout.writeln(
                                '$pkgPath has any dependencies in $dependencies');
                          }
                          allPaths.add(pkgPath);
                        } else {
                          if (verbose) {
                            stdout.writeln(
                                '$pkgPath does not have any dependencies in $dependencies');
                          }
                        }
                      }
                    }
                  }
                } else {
                  allPaths = await recursivePubPath([gitTopLevelPath],
                      dependencies: dependencies);
                }

                var newAll = allPackageWithDependency.toSet();
                for (var path in allPaths) {
                  if (pathsHandled.contains(path)) {
                    continue;
                  } else {
                    pathsHandled.add(path);
                  }
                  var subPubspec = await pathGetPubspecYamlMap(path);
                  var packageName = pubspecYamlGetPackageName(subPubspec)!;
                  newAll.add(packageName);
                  dependencies =
                      (dependencies.toSet()..add(packageName)).toList();
                }
                if (newAll.length == allPackageWithDependency.length) {
                  break;
                }
                allPackageWithDependency = newAll;
              }
              if (verbose) {
                stdout.writeln(
                    'allPackageWithDependency: $allPackageWithDependency');
              }
            }

            Future<void> handlePath(String path) async {
              stdout.writeln('# ${relative(path, from: topPath)}');
              var localPubspecMap = await pathGetPubspecYamlMap(path);
              var localPackageName =
                  pubspecYamlGetPackageName(localPubspecMap)!;

              if (packageName == localPackageName) {
                if (verbose) {
                  stdout.writeln('$packageName is the same as local package');
                }
                return;
              }
              var isFlutterPackage =
                  pubspecYamlSupportsFlutter(localPubspecMap);
              var dartOrFlutter = isFlutterPackage ? 'flutter' : 'dart';

              var hasDependency =
                  allPackageWithDependency.contains(localPackageName);
              if (!hasDependency) {
                if (verbose) {
                  stdout.writeln('$packageName not a dependency');
                }
                return;
              }
              var inlineOverrides = localPubspecMap['dependency_overrides']
                  ?.anyAs<Map?>()
                  ?.deepClone();
              // devPrint('inlineOverrides: $inlineOverrides');
              var pubspecOverrideFile =
                  File(join(path, 'pubspec_overrides.yaml'));
              var pubspecOverridesMap = Model();
              try {
                var existingText = await pubspecOverrideFile.readAsString();
                pubspecOverridesMap =
                    (loadYaml(existingText) as Object).anyAs<Map>().deepClone();
              } catch (_) {}

              var githubTop = normalize(absolute(findGithubTop(path)));
              var existing = pubspecOverridesMap['dependency_overrides']
                  ?.anyAs<Map?>()
                  ?.deepClone();

              var overrides = newModel();
              // Add inline (in pubspec.yaml) first.
              if (inlineOverrides != null) {
                overrides.addAll(inlineOverrides);
              }
              // Override with existing.
              if (existing != null) {
                overrides.addAll(existing);
              }
              pubspecOverridesMap['dependency_overrides'] = overrides;

              if (isRemove) {
                if (overrides.containsKey(packageName)) {
                  // if (verbose) {
                  var existingPackage = overrides[packageName];
                  stdout
                      .writeln('removing $packageName (was $existingPackage)');
                  overrides.remove(packageName);
                  // }
                } else {
                  if (verbose) {
                    stdout.writeln('$packageName not found in overrides');
                  }
                  return;
                }
              } else if (package == null) {
                if (info.def == null) {
                  throw StateError('Package not found $packageName');
                }
                if (hasDependency) {
                  overrides[packageName] = info.def;

                  stdout.writeln('Adding $packageName: def: ${info.def}');
                }
              } else {
                var dependencyPath = getDependencyLocalPath(
                    githubTop: githubTop,
                    gitUrl: package.gitUrl.v!,
                    gitPath: package.gitPath.v);
                var relativePath = relative(dependencyPath, from: path);

                if (hasDependency) {
                  var posixPath = toPosixPath(relativePath);
                  overrides[package.id] = {
                    'path': posixPath,
                  };
                  stdout.writeln('Adding $packageName: path: $relativePath');
                }
              }

              if (overrides.isNotEmpty) {
                var lines = pubspecOverridesMap.toYamlStrings('');
                var txt = linesToIoString(lines);
                await pubspecOverrideFile.writeAsString(txt);
              } else {
                await pubspecOverrideFile.delete(recursive: true);
              }
              var shell = Shell().cd(path);
              await shell.run('$dartOrFlutter pub get');
            }

            await handleTopPath(topPath, handlePath);

            //throw UnsupportedError('--$flagPubspcOverridesKey not implemented yet');
            return;
          } else {
            Future<void> handlePath(String path) async {
              stdout.writeln('# ${relative(path, from: topPath)}');
              var pubspecMap = await pathGetPubspecYamlMap('.');
              var localPackageName = pubspecYamlGetPackageName(pubspecMap)!;
              if (packageName == localPackageName) {
                if (verbose) {
                  stdout.writeln('$packageName is the same as local package');
                }
                return;
              }
              var isFlutterPackage = pubspecYamlSupportsFlutter(pubspecMap);
              var dartOrFlutter = isFlutterPackage ? 'flutter' : 'dart';

              var shell = Shell(workingDirectory: topPath);
              var dev = info.target == TkPubTarget.dev ||
                  (info.target == null && globalDev);
              var overrides = info.target == TkPubTarget.override ||
                  (info.target == null && globalPubspecOverrides);

              var prefix = dev ? 'dev:' : (overrides ? 'overrides:' : '');
              if (isRemove) {
                await shell.run('$dartOrFlutter pub remove $prefix'
                    '$packageName');
              } else {
                if (package == null) {
                  if (!force) {
                    throw StateError('Package not found $packageName');
                  }
                  toAdd.add(
                      topPath,
                      shellArgument('$prefix'
                          '$packageName'));
                } else {
                  toAdd.add(
                      topPath,
                      shellArgument('$prefix'
                          '$packageName:'
                          '${jsonEncode({
                            if (package.gitUrl.isNotNull)
                              'git': {
                                'url': package.gitUrl.v,
                                if (package.gitPath.isNotNull)
                                  'path': package.gitPath.v,
                                if (package.gitRef.isNotNull)
                                  'ref': package.gitRef.v,
                              },
                          })}'));
                }
              }
            }

            await handleTopPath(topPath, handlePath);
          }
        }
      }
    });
    for (var packagesToAdd in toAdd.group()) {
      var path = packagesToAdd.path;
      var pubspecMap = await pathGetPubspecYamlMap(path);
      var isFlutterPackage = pubspecYamlSupportsFlutter(pubspecMap);
      var dartOrFlutter = isFlutterPackage ? 'flutter' : 'dart';
      var shell = Shell(workingDirectory: path);
      await shell.run(
          '$dartOrFlutter pub add ${packagesToAdd.dartPubAddArgs.join(' ')} --directory .');
    }
    return true;
  }
}

extension on Map {
  Model sort() {
    var sorted = Model();
    var keys = (this.keys.toList()).cast<String>()..sort();
    for (var key in keys) {
      var value = this[key];
      if (value is Map) {
        value = value.sort();
      }
      sorted[key] = value;
    }
    return sorted;
  }

  List<String> toYamlStrings(String indent) {
    var lines = <String>[];
    var sorted = sort();
    for (var key in keys) {
      var value = sorted[key];
      if (value is Map) {
        lines.add('$indent$key:');
        lines.addAll(value.toYamlStrings('$indent  '));
      } else {
        lines.add('$indent$key: ${safeYamlString(value)}');
      }
    }
    return lines;
  }
}
