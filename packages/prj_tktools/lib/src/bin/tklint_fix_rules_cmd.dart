import 'package:args/args.dart';
import 'package:path/path.dart';
import 'package:process_run/stdio.dart';

import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:tekartik_prj_tktools/src/tklint/tklint_package.dart';
import 'package:tekartik_prj_tktools/src/yaml_edit.dart';
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
Future<void> tklintFixRules(
  String path, {
  String? analysisOptionsPath,
  TklintFixRulesOptions? options,
}) async {
  var include = options?.include;
  var verbose = options?.verbose ?? false;
  var package = TkLintPackage(path, verbose: verbose);
  analysisOptionsPath ??= 'analysis_options.yaml';

  TkLintRules rules;

  if (include != null) {
    var includePackagePath = await getPubPackageRoot(include);
    var includePackage = TkLintPackage(includePackagePath, verbose: verbose);
    var includeRules = await includePackage.getRules(
      relative(include, from: includePackagePath),
      handleInclude: true,
    );

    rules = await package.getRules(analysisOptionsPath);
    var thisIncludeRules = await package.getIncludeRules(analysisOptionsPath);

    rules.merge(includeRules);
    rules.removeDifferentRules(thisIncludeRules);
  } else {
    rules = await package.getRules(
      analysisOptionsPath,
      handleInclude: true,
      fromInclude: true,
    );
  }
  rules.removeObsoleteRules();

  if (verbose) {
    stdout.writeln('Resulting rules:');
    for (var text in rules.toStringList()) {
      stdout.writeln(text);
    }
  }

  rules.sort();
  var file = File(package.getAbsolutePath(analysisOptionsPath));
  final yamlEditor = YamlEditor(await file.readAsString());
  var yamlObject = rules.toYamlObject();
  // print(yamlObject);
  yamlEditor.updateOrAdd(['linter', 'rules'], yamlObject);
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
      ''',
      ) {
    parser.addOption(
      'include',
      help: 'Include first the rules from another project file',
    );
    parser.addFlag('recursive', help: 'Go recursive in dart projects');
  }

  @override
  FutureOr<bool> onRun() async {
    var rest = results.rest;
    var include = results.option('include');
    var recursive = results.flag('recursive');
    var verbose = results.flag('verbose') || this.verbose;
    String? analysisOptionsPath;
    if (rest.isNotEmpty) {
      analysisOptionsPath = rest.first;
    }
    var dirs = ['.'];
    if (recursive) {
      dirs = await recursivePubPath(dirs);
    }
    for (var dir in dirs) {
      await tklintFixRules(
        dir,
        analysisOptionsPath: analysisOptionsPath,
        options: TklintFixRulesOptions(include: include, verbose: verbose),
      );
    }
    return true;
  }
}
