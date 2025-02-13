import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub_copy_files_cmd.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub_list_cmd.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub_symlink_cmd.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:tekartik_prj_tktools/src/tkpub.dart';
import 'package:tekartik_prj_tktools/src/tkpub_db.dart';
import 'package:tekartik_prj_tktools/src/version.dart';

import 'tkpub_add_cmd.dart';
import 'tkpub_config_cmd.dart';

/// Force the config export path
const optionsConfigExportPath = 'config-export-path';

//late bool verbose;
/// tkpub command
class TkPubCommand extends ShellBinCommand {
  /// tkpub command
  TkPubCommand() : super(name: 'tkpub', version: packageVersion) {
    parser.addOption(optionsConfigExportPath, help: 'Force config export path');
    addCommand(TkPubConfigCommand());
    addCommand(_InitCommand());
    addCommand(TkPubAddCommand());
    addCommand(TkPubRemoveCommand());
    addCommand(TkPubListCommand());
    addCommand(TkPubClearCommand());
    addCommand(TkPubSymlinkCommand());
    addCommand(TkPubCopyFilesCommand());
  }

  @override
  FutureOr<bool> onRun() {
    return false;
  }
}

/// tkpub sub command
abstract class TkPubSubCommand extends ShellBinCommand {
  /// tkpub command
  TkPubCommand get tkPubCommand => parent as TkPubCommand;

  /// tkpub sub command
  TkPubSubCommand({required super.name, super.parser, super.description});

  String? _configExportPath;

  /// Get the config export path
  Future<String?> getConfigExportPath() async {
    return _configExportPath ??= await () async {
      var configExportPath =
          tkPubCommand.results.option(optionsConfigExportPath) ??
          await tkPubGetConfigExportPath();
      return configExportPath;
    }();
  }

  /// Run a db action
  Future<T> dbAction<T>(
    Future<T> Function(TkPubConfigDb db) action, {
    bool? write,
  }) async {
    return await tkPubDbAction(
      action,
      write: write,
      configExportPath: await getConfigExportPath(),
    );
  }
}

class _InitCommand extends ShellBinCommand {
  _InitCommand()
    : super(name: 'init', parser: ArgParser(allowTrailingOptions: true));

  @override
  FutureOr<bool> onRun() async {
    var rest = results.rest;
    if (rest.length != 1) {
      throw ArgumentError('One argument expected (path)');
    }
    var prefs = await openPrefs();
    prefs.setString(prefsKeyConfigExportPath, rest.first);
    return true;
  }
}

/// Compat.
Future<void> main(List<String> arguments) => tkPubMain(arguments);

/// Direct shell env Path dump run helper for testing.
Future<void> tkPubMain(List<String> arguments) async {
  try {
    await TkPubCommand().parseAndRun(arguments);
  } catch (e) {
    var verbose = arguments.contains('-v') || arguments.contains('--verbose');
    if (verbose) {
      rethrow;
    }
    stderr.writeln(e);
    exit(1);
  }
}
