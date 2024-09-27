import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub_copy_files_cmd.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub_list_cmd.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub_symlink_cmd.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:tekartik_prj_tktools/src/tkpub_db.dart';
import 'package:tekartik_prj_tktools/src/version.dart';

import 'tkpub_add_cmd.dart';
import 'tkpub_config_cmd.dart';

//late bool verbose;
/// tkpub command
class TkpubCommand extends ShellBinCommand {
  /// tkpub command
  TkpubCommand() : super(name: 'tkpub', version: packageVersion) {
    addCommand(TkpubConfigCommand());
    addCommand(_InitCommand());
    addCommand(TkpubAddCommand());
    addCommand(TkpubRemoveCommand());
    addCommand(TkpubListCommand());
    addCommand(TkpubClearCommand());
    addCommand(TkpubSymlinkCommand());
    addCommand(TkpubCopyFilesCommand());
  }

  @override
  FutureOr<bool> onRun() {
    // print('verbose: $verbose');
    return false;
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
    prefs.setString(prefsKeyPath, rest.first);
    return true;
  }
}

/// Compat.
Future<void> main(List<String> arguments) => tkpubMain(arguments);

/// Direct shell env Path dump run helper for testing.
Future<void> tkpubMain(List<String> arguments) async {
  try {
    await TkpubCommand().parseAndRun(arguments);
  } catch (e) {
    var verbose = arguments.contains('-v') || arguments.contains('--verbose');
    if (verbose) {
      rethrow;
    }
    stderr.writeln(e);
    exit(1);
  }
}
