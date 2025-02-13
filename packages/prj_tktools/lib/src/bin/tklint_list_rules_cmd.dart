import 'package:args/args.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:tekartik_prj_tktools/tklint.dart';

/// Clear
class TklintListRulesCommand extends ShellBinCommand {
  /// Clear
  TklintListRulesCommand()
    : super(
        name: 'list-rules',
        parser: ArgParser(allowTrailingOptions: true),
        description: '''
List rules overrides over another file
      ''',
      ) {
    parser.addFlag('force-any', help: 'List all rules as rule: true|false');
    parser.addFlag(
      'no-include',
      help: 'Do not handle included files',
      negatable: false,
    );
    parser.addOption('from', help: 'Added from file/dep');
    parser.addFlag('from-include', help: 'Added from direct include');
  }

  @override
  FutureOr<bool> onRun() async {
    var verbose = this.verbose;
    var rest = results.rest;
    var forceAny = results.flag('force-any');
    var handleInclude = !results.flag('no-include');
    var from = results.option('from');
    var fromInclude = results.flag('from-include');
    String analysisOptionsPath;
    if (rest.isEmpty) {
      analysisOptionsPath = 'analysis_options.yaml';
    } else {
      analysisOptionsPath = rest.first;
    }
    var package = TkLintPackage('.', verbose: verbose);
    var rules = await package.getRules(
      analysisOptionsPath,
      handleInclude: handleInclude,
      fromInclude: fromInclude,
    );

    if (from != null) {
      var fromRules = await package.getRules(
        await package.resolvePath(from),
        handleInclude: true,
      );
      rules.removeDifferentRules(fromRules);
    }
    for (var text in rules.toStringList(forceAny: forceAny)) {
      stdout.writeln(text);
    }
    return true;
  }
}
