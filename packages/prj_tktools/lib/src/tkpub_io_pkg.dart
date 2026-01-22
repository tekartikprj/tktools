import 'dart:io';

import 'package:dev_build/build_support.dart';
import 'package:dev_build/menu/menu_run_ci.dart';

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

  /// Try to run build_runner watch
  Future<bool> tryWatch() async {
    if (await _checkBuildRunnerSetup()) {
      await shell.run(
        'dart run build_runner watch --delete-conflicting-outputs',
      );
      return true;
    }
    return false;
  }
}
