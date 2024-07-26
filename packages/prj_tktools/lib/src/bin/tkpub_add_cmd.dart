import 'package:args/args.dart';
import 'package:cv/cv.dart';
import 'package:path/path.dart';
import 'package:process_run/shell.dart';
import 'package:process_run/stdio.dart';
// ignore: implementation_imports
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:tekartik_sc/git.dart';
import 'package:yaml/yaml.dart';

import 'tkpub.dart';

const flagDevKey = 'dev';
const flagForceKey = 'force';
const flagOverridesKey = 'overrides';
const flagPubspecOverridesKey = 'pubspec-overrides';
const flagRecursiveKey = 'recursive';

class TkpubClearCommand extends TkpubAddRemoveCommand {
  @override
  bool get isClear => true;
  TkpubClearCommand()
      : super(name: 'clear', parser: ArgParser(allowTrailingOptions: true)) {
    parser.addFlag(flagPubspecOverridesKey,
        help: 'Clear pubspec_overrides.yaml');
    parser.addFlag(flagRecursiveKey,
        help: 'Go to every subfolder (pubspec-overrides only for now)');
  }
}

class TkpubRemoveCommand extends TkpubAddRemoveCommand {
  @override
  bool get isRemove => true;
  TkpubRemoveCommand()
      : super(name: 'remove', parser: ArgParser(allowTrailingOptions: true)) {
    parser.addFlag(flagDevKey, help: 'Remove from dev_dependencies mode');
    parser.addFlag(flagOverridesKey, help: 'Remove from dependecy_overrides');
    parser.addFlag(flagPubspecOverridesKey,
        help: 'Remove from pubspec_overrides.yaml');
    parser.addFlag(flagRecursiveKey,
        help: 'Go to every subfolder (pubspec-overrides only for now)');
  }
}

class TkpubAddCommand extends TkpubAddRemoveCommand {
  @override
  bool get isAdd => true;
  TkpubAddCommand()
      : super(name: 'add', parser: ArgParser(allowTrailingOptions: true)) {
    parser.addFlag(flagDevKey, help: 'Add to dev_dependencies mode');
    parser.addFlag(flagOverridesKey, help: 'Add to dependecy_overrides');
    parser.addFlag(flagForceKey,
        help: 'Force adding (hosted only or specified)');
    parser.addFlag(flagPubspecOverridesKey,
        help: 'Remove from pubspec_overrides.yaml');
    parser.addFlag(flagRecursiveKey,
        help: 'Go to every subfolder (pubspec-overrides only for now)');
  }
}

abstract class TkpubAddRemoveCommand extends ShellBinCommand {
  bool get isAdd => false;
  bool get isRemove => false;
  bool get isClear => false;
  TkpubAddRemoveCommand({required super.name, super.parser});
  @override
  FutureOr<bool> onRun() async {
    var dev = !isClear ? results.flag(flagDevKey) : false;
    var overrides = !isClear ? results.flag(flagOverridesKey) : false;
    var pubspecOverrides = results.flag(flagPubspecOverridesKey);
    var recursive = results.flag(flagRecursiveKey);
    var force = isAdd ? results.flag(flagForceKey) : false;

    if (pubspecOverrides) {
      if (dev || overrides) {
        throw ArgumentError(
            'Cannot use --$flagPubspecOverridesKey with --$flagDevKey or --$flagOverridesKey');
      }
    }

    var rest = results.rest;
    if (isClear && rest.isNotEmpty) {
      throw ArgumentError('No argument expected for clear');
    }
    if (!isClear && rest.length != 1) {
      throw ArgumentError('One argument expected (package name)');
    }
    var verbose = this.verbose ?? false;

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

    await tkpubDbAction((db) async {
      final topPath = '.';

      if (isClear) {
        if (pubspecOverrides) {
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
        var packageNameOrDef = rest.first.trim();
        if (packageNameOrDef.startsWith("'") &&
            packageNameOrDef.endsWith("'")) {
          packageNameOrDef =
              packageNameOrDef.substring(1, packageNameOrDef.length - 1);
        }
        var packageName = packageNameOrDef.split(':').first;
        // True for add only!
        //var packageHasDefinition = packageName != packageNameOrDef;
        var package = await db.getPackageOrNull(packageName);

        if (pubspecOverrides) {
          var dependencies = [packageName];

          /// Find all local project in git
          var gitTopLevelPath = await findGitTopLevelPath(topPath);
          var allPackageWithDependency = <String>{};
          if (gitTopLevelPath != null) {
            var pathsHandled = <String>{};
            while (true) {
              var allPaths = await recursivePubPath([gitTopLevelPath],
                  dependencies: dependencies);

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
            var localPackageName = pubspecYamlGetPackageName(localPubspecMap)!;
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
                stdout.writeln('removing $packageName (was $existingPackage)');
                overrides.remove(packageName);
                // }
              } else {
                if (verbose) {
                  stdout.writeln('$packageName not found in overrides');
                }
                return;
              }
            } else if (package == null) {
              var parts = packageNameOrDef.split(':');
              if (parts.length == 1) {
                throw StateError('Package not found $packageName');
              }
              if (hasDependency) {
                var def = packageNameOrDef.substring(parts[0].length + 1);
                print(def);
                overrides[packageName] = jsonDecode(def);

                stdout.writeln('Adding $packageName: def: $def');
              }
            } else {
              var dependencyGithubPath = Uri.parse(package.gitUrl.v!).path;
              if (dependencyGithubPath.endsWith('.git')) {
                dependencyGithubPath = dependencyGithubPath.substring(
                    0, dependencyGithubPath.length - '.git'.length);
              }
              if (dependencyGithubPath.startsWith('/')) {
                dependencyGithubPath = dependencyGithubPath.substring(1);
              }
              var gitPath = package.gitPath.v?.trim();
              var dependencyPath = normalize(absolute(joinAll([
                githubTop,
                dependencyGithubPath,
                if (gitPath?.isNotEmpty ?? false) gitPath!
              ])));
              var relativePath = relative(dependencyPath, from: path);

              if (hasDependency) {
                overrides[package.id] = {
                  'path': relativePath,
                };
                stdout.writeln('Adding $packageName: path: $relativePath');
              }
            }

            if (overrides.isNotEmpty) {
              var lines = pubspecOverridesMap.toYamlStrings('');
              var txt = '${lines.join('\n')}\n';
              await pubspecOverrideFile.writeAsString(txt);
            } else {
              await pubspecOverrideFile.delete(recursive: true);
            }
          }

          await handleTopPath(topPath, handlePath);

          //throw UnsupportedError('--$flagPubspcOverridesKey not implemented yet');
          return;
        } else {
          Future<void> handlePath(String path) async {
            stdout.writeln('# ${relative(path, from: topPath)}');
            var pubspecMap = await pathGetPubspecYamlMap('.');
            var isFlutterPackage = pubspecYamlSupportsFlutter(pubspecMap);
            var dartOrFlutter = isFlutterPackage ? 'flutter' : 'dart';

            var shell = Shell(workingDirectory: topPath);

            var prefix = dev ? 'dev:' : (overrides ? 'overrides:' : '');
            if (isRemove) {
              await shell.run('$dartOrFlutter pub remove $prefix'
                  '$packageName');
            } else {
              if (package == null) {
                if (!force) {
                  throw StateError('Package not found $packageName');
                }
                await shell
                    .run('$dartOrFlutter pub add ${shellArgument('$prefix'
                            '$packageName')}'
                        ' --directory .');
              } else {
                await shell
                    .run('$dartOrFlutter pub add ${shellArgument('$prefix'
                            '$packageName:'
                            '${jsonEncode({
                      if (package.gitUrl.isNotNull)
                        'git': {
                          'url': package.gitUrl.v,
                          if (package.gitPath.isNotNull)
                            'path': package.gitPath.v,
                          if (package.gitRef.isNotNull) 'ref': package.gitRef.v,
                        },
                    })}')}'
                        ' --directory .');
              }
            }
          }

          await handleTopPath(topPath, handlePath);
        }
      }
    });
    return true;
  }
}

String findGithubTop(String dirPath) {
  var dir = Directory(normalize(dirPath)).absolute;
  while (dir.path != '/') {
    if (Directory(join(dir.path, 'github.com', 'tekartik')).existsSync()) {
      return join(dir.path, 'github.com');
    }
    dir = dir.parent;
  }
  throw StateError('Cannot find top github.com dir');
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
        lines.add('$indent$key: $value');
      }
    }
    return lines;
  }
}

String toYamlString(Object value) {
  if (value is Map) {
    return 'null';
  }
  return jsonEncode(value);
}