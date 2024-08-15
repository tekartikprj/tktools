import 'package:args/args.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/bin/tklint_list_rules_cmd.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Clear
class TklintFixRulesCommand extends ShellBinCommand {
  /// Clear
  TklintFixRulesCommand()
      : super(
            name: 'fix-rules',
            parser: ArgParser(allowTrailingOptions: true),
            description: '''
Fix rules overrides over another file
      ''');

  @override
  FutureOr<bool> onRun() async {
    var verbose = this.verbose ?? false;
    var rest = results.rest;
    String analysisOptionsPath;
    if (rest.isEmpty) {
      analysisOptionsPath = 'analysis_options.yaml';
    } else {
      analysisOptionsPath = rest.first;
    }
    var package = Package('.', verbose: verbose);
    var rules = await package.getRules(analysisOptionsPath,
        handleInclude: true, fromInclude: true);

    for (var text in rules.toStringList()) {
      stdout.writeln(text);
    }

    final yamlEditor =
        YamlEditor(await File(analysisOptionsPath).readAsString());
    var yamlObject = rules.toYamlObject();
    // print(yamlObject);
    yamlEditor.update(['linter', 'rules'], yamlObject);
    return true;
  }
}
