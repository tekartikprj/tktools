import 'package:dev_build/menu/menu_run_ci.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';

/// Alias for PubIoPackage
typedef TkPubPackage = PubIoPackage;

/// Extension for TkPubPackage
extension TkPubPackageExt on TkPubPackage {
  /// prompt bool
  Future<bool> promptBool(String message, {bool defaultValue = false}) async {
    stdout.write('$message [y/N]: ');
    var input = stdin.readLineSync();
    if (input == null) return defaultValue;
    return input.toLowerCase() == 'y';
  }

  /// Check if the package has a build_runner dependency
  Future<bool> hasBuildRunnerDependency() async {
    return await hasDependency(_buildRunnerPackageName);
  }

  /// Analyze the package
  Future<void> analyze() async {
    if (isFlutter) {
      await shell.run('''
      # Analyze code
      flutter analyze --no-pub .
    ''');
    } else {
      await shell.run('''
      # Analyze code
      dart analyze --fatal-warnings --fatal-infos .
  ''');
    }
  }

  /// Check if the package has a specific dependency
  Future<bool> hasDependency(String packageName) async {
    return pubspecYamlHasAnyDependencies(pubspecYaml, [packageName]);
  }

  /// Add a dev dependency to the package
  Future<void> addDevDependency(String packageName) async {
    var dof = this.dof;
    await shell.run('$dof pub add --dev $packageName');
  }

  static const _buildRunnerPackageName = 'build_runner';
  Future<bool> _checkBuildRunnerSetup({bool? forceInterractive = true}) async {
    if (!await hasBuildRunnerDependency()) {
      if (stdin.hasTerminal || (forceInterractive ?? false)) {
        var add = await promptBool(
          'build_runner dependency not found in $path pubspec.yaml. Do you want to add it?',
          defaultValue: true,
        );
        if (add) {
          await addDevDependency(_buildRunnerPackageName);
          return true;
        }
      } else {
        stderr.writeln(
          'Warning: build_runner dependency not found in $path pubspec.yaml',
        );
        exit(1);
      }
    } else {
      return true;
    }
    return false;
  }

  /// Compat
  @Deprecated('Use tryBuildRunnerWatch')
  Future<bool> tryWatch({bool? deleteConflictingOutput}) =>
      tryBuildRunnerWatch(deleteConflictingOutput: deleteConflictingOutput);

  /// Try to run build_runner watch
  Future<bool> tryBuildRunnerWatch({bool? deleteConflictingOutput}) async {
    deleteConflictingOutput ??= false;
    if (await _checkBuildRunnerSetup()) {
      await shell.run(
        'dart run build_runner watch'
        '${deleteConflictingOutput ? ' --delete-conflicting-outputs' : ''}',
      );
      return true;
    }
    return false;
  }

  /// Try to run build_runner watch
  Future<bool> tryBuildRunnerBuild({bool? deleteConflictingOutput}) async {
    deleteConflictingOutput ??= false;
    if (await _checkBuildRunnerSetup()) {
      await shell.run(
        'dart run build_runner build'
        '${deleteConflictingOutput ? ' --delete-conflicting-outputs' : ''}',
      );
      return true;
    }
    return false;
  }
}

/// Top path
class TkPubTopPath {
  /// Actual path
  final String path;

  /// Top path
  TkPubTopPath({this.path = '.'});

  /// Recursive action for build runners
  Future<void> recursiveBuildRunnerActions(
    Future<void> Function(String path) action,
  ) async {
    return shellStdioLinesGrouper.runZoned(() async {
      await recursiveActions(
        [path],
        action: action,
        dependencies: ['build_runner'],
      );
    });
  }
}
