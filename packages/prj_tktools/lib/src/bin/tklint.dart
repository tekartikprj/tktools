import 'dart:async';
import 'dart:io';

import 'package:tekartik_prj_tktools/src/bin/tklint_fix_rules_cmd.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';

import 'tklint_list_rules_cmd.dart';

//late bool verbose;
/// tkpub command
class TklintCommand extends ShellBinCommand {
  /// tkpub command
  TklintCommand() : super(name: 'tklint') {
    addCommand(TklintListRulesCommand());
    addCommand(TklintFixRulesCommand());
  }

  @override
  FutureOr<bool> onRun() {
    // print('verbose: $verbose');
    return false;
  }
}

/// Compat
Future<void> main(List<String> arguments) => tklintMain(arguments);

/// Direct shell env Path dump run helper for testing.
Future<void> tklintMain(List<String> arguments) async {
  try {
    await TklintCommand().parseAndRun(arguments);
  } catch (e) {
    var verbose = arguments.contains('-v') || arguments.contains('--verbose');
    if (verbose) {
      rethrow;
    }
    stderr.writeln(e);
    exit(1);
  }
}
