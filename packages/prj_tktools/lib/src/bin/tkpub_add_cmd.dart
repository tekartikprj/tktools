import 'package:args/args.dart';
import 'package:process_run/stdio.dart';
// ignore: implementation_imports
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub.dart';
import 'package:tekartik_prj_tktools/src/tkpub/tkpub_deps.dart';

/// Dev flag
const flagDevKey = 'dev';

/// Direct dependency flag
const flagDirectKey = 'direct';

/// Force flag
const flagForceKey = 'force';

/// Overrides flag
const flagOverridesKey = 'overrides';

/// pub spec overrides
const flagPubspecOverridesKey = 'pubspec-overrides';

/// direct & pub spec overrides
const flagDirectAndPubspecOverridesKey = 'direct-and-pubspec-overrides';

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
    parser.addFlag(flagOverridesKey, help: 'Remove from dependency_overrides');
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
    parser.addFlag(flagDirectKey, help: 'Add to dependencies mode');
    parser.addFlag(flagOverridesKey,
        abbr: 'o', help: 'Add to dependency_overrides');
    parser.addFlag(flagForceKey,
        abbr: 'f', help: 'Force adding (hosted only or specified)');
    parser.addFlag(flagPubspecOverridesKey,
        abbr: 'p', help: 'Add to pubspec_overrides.yaml');
    parser.addFlag(flagDirectAndPubspecOverridesKey,
        abbr: 'b', help: 'Add to direct deps and pubspec_overrides.yaml');
    parser.addFlag(flagRecursiveKey,
        abbr: 'r',
        help: 'Go to every subfolder (pubspec-overrides only for now)');
    parser.addFlag(flagReadConfigKey,
        abbr: 'c', help: 'Read config instead of filtering by dependencies');
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
    var directAndPubspecOverrides =
        results.flag(flagDirectAndPubspecOverridesKey);
    var globalDirect = results.flag(flagDirectKey);

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

    /// Direct or dev dependencies to add.

    final topPath = '.';
    if (isClear) {
      var options = TkPubDepsManagerOptions(
          pubspecOverrides: globalPubspecOverrides,
          recursive: recursive,
          verbose: verbose);

      var manager = TkPubDepsManager(path: topPath, options: options);
      await manager.clear();
      return true;
    }
    var options = TkPubDepsManagerOptions(
        pubspecOverrides: globalPubspecOverrides || directAndPubspecOverrides,
        directDependencies: globalDirect || directAndPubspecOverrides,
        devDependencies: globalDev,
        overrideDependencies: globalOverrides,
        recursive: recursive,
        configExportPath: await getConfigExportPath(),
        readConfig: readConfig,
        verbose: verbose,
        force: force);
    var manager = TkPubDepsManager(path: topPath, options: options);
    if (isAdd) {
      await manager.add(rest);
    } else if (isRemove) {
      await manager.remove(rest);
    } else {
      throw UnsupportedError('isClear not implemented yet');
    }
    return true;
  }
}
