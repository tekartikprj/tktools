import 'package:collection/collection.dart';
import 'package:cv/cv.dart';
import 'package:dev_build/menu/menu_run_ci.dart';
import 'package:dev_build/package.dart';
import 'package:dev_build/shell.dart';
import 'package:fs_shim/utils/io/read_write.dart' show linesToIoString;
import 'package:fs_shim/utils/path.dart' show toPosixPath;
import 'package:fs_shim/utils/path.dart';
import 'package:path/path.dart';
import 'package:process_run/shell.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
// ignore: implementation_imports
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub_package_info.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:tekartik_prj_tktools/src/utils.dart';
import 'package:tekartik_prj_tktools/tkpub.dart';
import 'package:tekartik_prj_tktools/yaml_edit.dart';
import 'package:tekartik_sc/git.dart';
import 'package:yaml/yaml.dart';

/// Options
class TkPubDepsManagerOptions {
  /// pubspec overrides global
  final bool pubspecOverrides;

  /// Direct deps
  final bool directDependencies;

  /// Dev deps
  final bool devDependencies;

  /// Override deps
  final bool overridesDependencies;

  /// Recursive
  final bool recursive;

  /// Overriden config export path
  final String? configExportPath;

  /// Read config instead of just getting dependencies
  final bool readConfig;

  /// Verbose
  final bool verbose;

  /// Force
  final bool force;

  /// Constructor
  TkPubDepsManagerOptions({
    bool? pubspecOverrides,
    bool? recursive,
    this.configExportPath,
    bool? readConfig,
    bool? verbose,
    bool? directDependencies,
    bool? devDependencies,
    bool? overrideDependencies,
    bool? force,
  }) : pubspecOverrides = pubspecOverrides ?? false,
       directDependencies = directDependencies ?? false,
       devDependencies = devDependencies ?? false,
       overridesDependencies = overrideDependencies ?? false,
       recursive = recursive ?? false,
       readConfig = readConfig ?? false,
       verbose = verbose ?? false,
       force = force ?? false;
}

/// TkPubDepsManager
class TkPubDepsManager {
  /// options
  final TkPubDepsManagerOptions options;

  /// Path
  final String path;

  /// Constructor
  TkPubDepsManager({String? path, TkPubDepsManagerOptions? options})
    : path = path ?? '.',
      options = options ?? TkPubDepsManagerOptions();

  Future<void> _handleTopPath(
    String path,
    Future<void> Function(String path) handlePath,
  ) async {
    if (options.recursive) {
      for (var subPath in await recursivePubPath([path])) {
        await handlePath(subPath);
      }
    } else {
      await handlePath(path);
    }
  }

  /// Clear
  Future<void> clear() async {
    if (!options.pubspecOverrides) {
      stderr.writeln('Must specify --pubspec-overrides');
    }
    Future<void> handlePath(String path) async {
      var workPath = await pathGetResolvedWorkPath(path);
      var pubspecOverrideFile = File(
        await pathGetPubspecOverridesYamlPath(path),
      );
      stdout.writeln('# ${relative(path, from: workPath)}');

      if (pubspecOverrideFile.existsSync()) {
        await pubspecOverrideFile.delete();
        stdout.writeln('Removed pubspec_overrides.yaml');
      }
    }

    await _handleTopPath(path, handlePath);
  }

  Future<T> _dbAction<T>(
    Future<T> Function(TkPubConfigDb db) action, {
    bool? write,
  }) async {
    return await tkPubDbAction(
      action,
      write: write,
      configExportPath: options.configExportPath,
    );
  }

  Future<void> _addOrRemove(List<String> deps, {bool isRemove = false}) async {
    /// Direct or dev dependencies to add.
    final toAdd = _PackageToAddList();

    await _dbAction((db) async {
      final topPath = '.';

      for (var dep in deps) {
        var info = TkPubPackageInfo.parse(dep);
        var packageName = info.name;
        // True for add only!
        //var packageHasDefinition = packageName != packageNameOrDef;
        var package = await db.getPackageOrNull(
          packageName,
          addMissingRef: true,
        );

        var pubspecOverrides =
            info.target == TkPubTarget.pubspecOverrides ||
            (info.target == null && options.pubspecOverrides);

        var bothDepsAndPubspecOverrides =
            pubspecOverrides &&
            (options.devDependencies || options.directDependencies);

        /// Regular dependencies
        if (!pubspecOverrides || bothDepsAndPubspecOverrides) {
          // Not pubspec overrides
          Future<void> handlePath(String path) async {
            var subPath = relative(path, from: topPath);
            stdout.writeln('# $subPath');
            var ioPackage = PubIoPackage(subPath);
            await ioPackage.ready;
            var pubspecMap = ioPackage.pubspecYaml;
            var dofPub = ioPackage.dofPub;
            var dartPackage = DartPackageReader.pubspecYaml(pubspecMap);
            var localPackageName = pubspecYamlGetPackageName(pubspecMap)!;
            if (packageName == localPackageName) {
              if (options.verbose) {
                stdout.writeln('$packageName is the same as local package');
              }
              return;
            }
            var shell = Shell(workingDirectory: subPath);
            var dev =
                info.target == TkPubTarget.dev ||
                (info.target == null && options.devDependencies);
            var overrides =
                info.target == TkPubTarget.override ||
                (info.target == null && options.overridesDependencies);

            var kind =
                dev
                    ? PubDependencyKind.dev
                    : (overrides
                        ? PubDependencyKind.override
                        : PubDependencyKind.direct);

            var prefix = dev ? 'dev:' : (overrides ? 'overrides:' : '');
            if (isRemove) {
              await shell.run(
                '$dofPub remove $prefix'
                '$packageName',
              );
            } else {
              if (package == null) {
                if (!options.force) {
                  throw StateError('Package not found $packageName');
                }
                toAdd.add(
                  subPath,
                  shellArgument(
                    '$prefix'
                    '$packageName',
                  ),
                );
              } else {
                var existingDependencyMap = dartPackage.getDependencyObject(
                  dependency: packageName,
                  kind: kind,
                );
                var newDependencyMap = {
                  packageName: {
                    if (package.gitUrl.isNotNull)
                      'git': {
                        'url': package.gitUrl.v,
                        if (package.gitPath.isNotNull)
                          'path': package.gitPath.v,
                        if (package.gitRef.isNotNull) 'ref': package.gitRef.v,
                      },
                  },
                };
                /*
                print(jsonPretty(existingDependencyMap));
                print('vs');
                print(jsonPretty(newDependencyMap));
                */
                if (const DeepCollectionEquality().equals(
                  existingDependencyMap,
                  newDependencyMap,
                )) {
                  stdout.writeln(
                    'Dependency $kind $packageName already configured',
                  );
                } else {
                  toAdd.add(
                    subPath,
                    shellArgument(
                      '$prefix'
                      '$packageName:'
                      '${jsonEncode({
                        if (package.gitUrl.isNotNull) 'git': {'url': package.gitUrl.v, if (package.gitPath.isNotNull) 'path': package.gitPath.v, if (package.gitRef.isNotNull) 'ref': package.gitRef.v},
                      })}',
                    ),
                  );
                }
              }
            }
          }

          await _handleTopPath(topPath, handlePath);
        }

        /// Overrides
        if (pubspecOverrides) {
          var dependencies = [packageName];

          var allPackageWithDependency = <String>{};

          if (bothDepsAndPubspecOverrides || options.force) {
            /// Also specified as a dependency
            /// So don't check other projects
          } else {
            /// Find all local project in git
            var gitTopLevelPath = await findGitTopLevelPath(topPath);

            if (gitTopLevelPath != null) {
              var pathsHandled = <String>{};
              while (true) {
                List<String> allPaths;

                allPaths = await recursivePubPath(
                  [gitTopLevelPath],
                  dependencies: dependencies,
                  readConfig: options.readConfig,
                );

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
              if (options.verbose) {
                stdout.writeln(
                  'allPackageWithDependency: $allPackageWithDependency',
                );
              }
            }
          }

          Future<void> handlePath(String path) async {
            stdout.writeln('# ${relative(path, from: topPath)}');
            var prj = PubIoPackage(path);
            await prj.ready;
            var dofPub = prj.dofPub;
            var localPubspecMap = prj.pubspecYaml;
            var localPackageName = pubspecYamlGetPackageName(localPubspecMap)!;

            if (packageName == localPackageName) {
              if (options.verbose) {
                stdout.writeln('$packageName is the same as local package');
              }
              return;
            }
            var hasDependency =
                allPackageWithDependency.contains(localPackageName) ||
                bothDepsAndPubspecOverrides;
            if (!hasDependency && !options.force) {
              if (options.verbose) {
                stdout.writeln('$packageName not a dependency');
              }
              return;
            }
            var inlineOverrides =
                localPubspecMap['dependency_overrides']
                    ?.anyAs<Map?>()
                    ?.deepClone();
            // devPrint('inlineOverrides: $inlineOverrides');
            var workPath = await pathGetResolvedWorkPath(path);
            var pubspecOverrideFile = File(
              await pathGetPubspecOverridesYamlPath(path),
            );

            var pubspecOverridesMap = Model();
            try {
              var existingText = await pubspecOverrideFile.readAsString();
              pubspecOverridesMap =
                  (loadYaml(existingText) as Object).anyAs<Map>().deepClone();
            } catch (_) {}

            var githubTop = normalize(absolute(findGithubTop(path)));
            var existing =
                pubspecOverridesMap['dependency_overrides']
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
                // if (options.verbose) {
                var existingPackage = overrides[packageName];
                stdout.writeln('removing $packageName (was $existingPackage)');
                overrides.remove(packageName);
                // }
              } else {
                if (options.verbose) {
                  stdout.writeln('$packageName not found in overrides');
                }
                return;
              }
            } else if (package == null) {
              if (info.def == null) {
                throw StateError('Package not found $packageName');
              }
              if (hasDependency
                  /// Ok if we also add it as a dependency
                  ||
                  bothDepsAndPubspecOverrides) {
                overrides[packageName] = info.def;

                stdout.writeln('Adding $packageName: def: ${info.def}');
              }
            } else {
              var dependencyPath = getDependencyLocalPath(
                githubTop: githubTop,
                gitUrl: package.gitUrl.v!,
                gitPath: package.gitPath.v,
              );
              var relativePath = relative(dependencyPath, from: workPath);

              if (hasDependency || options.force) {
                var posixPath = toPosixPath(relativePath);
                overrides[package.id] = {'path': posixPath};
                stdout.writeln(
                  'Adding to pubspec_overrides.yaml $packageName: path: $relativePath',
                );
              }
            }

            if (overrides.isNotEmpty) {
              var lines = pubspecOverridesMap.toYamlStrings('');
              var txt = linesToIoString(lines);
              await pubspecOverrideFile.writeAsString(txt);
            } else {
              if (pubspecOverrideFile.existsSync()) {
                await pubspecOverrideFile.delete();
              }
            }
            // Only perform a get if non is planned yet
            var shouldPubGet = true;
            for (var toAddPath in toAdd.list.map((e) => e.path)) {
              if (toAddPath == path) {
                shouldPubGet = false;
                break;
              }
            }

            if (shouldPubGet) {
              var shell = Shell().cd(path);
              await shell.run('$dofPub get');
            }
          }

          await _handleTopPath(topPath, handlePath);

          //throw UnsupportedError('--$flagPubspcOverridesKey not implemented yet');
          return;
        }
      }
    });
    for (var packagesToAdd in toAdd.group()) {
      var path = packagesToAdd.path;
      var ioPackage = PubIoPackage(path);
      await ioPackage.ready;
      var dofPub = ioPackage.dofPub;
      var shell = Shell(workingDirectory: path);
      await shell.run(
        '$dofPub add ${packagesToAdd.dartPubAddArgs.join(' ')} --directory .',
      );
    }
  }

  /// Add dependencies
  Future<void> add(List<String> deps) async {
    await _addOrRemove(deps);
  }

  /// Remove dependencies
  Future<void> remove(List<String> deps) async {
    await _addOrRemove(deps, isRemove: true);
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
