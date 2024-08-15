import 'package:args/args.dart';
import 'package:path/path.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/bin/tklint_list_rules_cmd.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:tekartik_pub/io.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Fix rules options
class TklintFixRulesOptions {
  /// Include file
  final String? include;

  /// Verbose
  final bool verbose;

  /// Fix rules options
  TklintFixRulesOptions({this.include, this.verbose = false});
}

/// Fix rules
Future<void> tklintFixRules(String path,
    {String? analysisOptionsPath, TklintFixRulesOptions? options}) async {
  var include = options?.include;
  var verbose = options?.verbose ?? false;
  var package = Package(path, verbose: verbose);
  analysisOptionsPath ??= 'analysis_options.yaml';

  Rules rules;

  if (include != null) {
    var includePackagePath = await getPubPackageRoot(include);
    var includePackage = Package(includePackagePath, verbose: verbose);
    var includeRules = await includePackage.getRules(
        relative(include, from: includePackagePath),
        handleInclude: true);

    rules = await package.getRules(analysisOptionsPath);
    var thisIncludeRules = await package.getIncludeRules(analysisOptionsPath);

    rules.merge(includeRules);
    rules.removeDifferentRules(thisIncludeRules);
  } else {
    rules = await package.getRules(analysisOptionsPath,
        handleInclude: true, fromInclude: true);
  }

  if (verbose) {
    stdout.writeln('Resulting rules:');
    for (var text in rules.toStringList()) {
      stdout.writeln(text);
    }
  }

  rules.sort();
  var file = File(analysisOptionsPath);
  final yamlEditor = YamlEditor(await file.readAsString());
  var yamlObject = rules.toYamlObject();
  // print(yamlObject);
  yamlEditor.update(['linter', 'rules'], yamlObject);
  await file.writeAsString(yamlEditor.toString());
}

/// Clear
class TklintFixRulesCommand extends ShellBinCommand {
  /// Clear
  TklintFixRulesCommand()
      : super(
            name: 'fix-rules',
            parser: ArgParser(allowTrailingOptions: true),
            description: '''
Fix rules overrides over another file
      ''') {
    parser.addOption('include',
        help: 'Include first the rules from another project file');
  }

  @override
  FutureOr<bool> onRun() async {
    var verbose = this.verbose ?? false;
    var rest = results.rest;
    var include = results.option('include');
    String? analysisOptionsPath;
    if (rest.isNotEmpty) {
      analysisOptionsPath = rest.first;
    }
    await tklintFixRules('.',
        analysisOptionsPath: analysisOptionsPath,
        options: TklintFixRulesOptions(include: include, verbose: verbose));
    return true;
  }
}
