import 'package:args/args.dart';
import 'package:cv/cv.dart';
import 'package:dev_build/build_support.dart';
import 'package:path/path.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_common_utils/string_utils.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:yaml/yaml.dart';

/// Rule
class Rule {
  /// Name
  final String name;

  /// Enabled
  final bool enabled;

  /// Rule
  Rule(this.name, this.enabled);

  /// To any string
  String toAnyString() {
    return '$name: $enabled';
  }

  /// To enabled string (for list)
  String toEnabledString() {
    return '- $name';
  }

  @override
  int get hashCode => name.hashCode;
  @override
  bool operator ==(Object other) {
    if (other is Rule) {
      return (name == other.name) && (enabled == other.enabled);
    }
    return false;
  }

  @override
  String toString() => toAnyString();
}

/// Rules
class Rules {
  /// Rules
  late final List<Rule> rules;

  /// Rules
  Rules([List<Rule>? rules]) {
    this.rules = rules != null ? List.of(rules) : <Rule>[];
  }

  void _removeRuleNames(List<String> ruleNames) {
    rules.removeWhere((element) => ruleNames.contains(element.name));
  }

  List<String> get _ruleNames {
    return rules.map((e) => e.name).toList();
  }

  /// Merge (rules overrides existing rules)
  void merge(Rules rules) {
    _removeRuleNames(rules._ruleNames);
    this.rules.addAll(rules.rules);
  }

  /// Add a rule
  void add(Rule rule) {
    rules.removeWhere((element) => element.name == rule.name);
    rules.add(rule);
  }

  /// Sort
  void sort() {
    rules.sort((a, b) => a.name.compareTo(b.name));
  }

  /// True if all rules are enabled
  bool get areAllEnabled {
    for (var rule in rules) {
      if (!rule.enabled) {
        return false;
      }
    }
    return true;
  }

  /// Check if a rule is enabled
  bool isEnabled(String name) {
    for (var rule in rules) {
      if (rule.name == name) {
        return rule.enabled;
      }
    }
    return false;
  }

  /// To string list
  List<String> toStringList({bool? forceAny}) {
    if (areAllEnabled && !(forceAny ?? false)) {
      return rules.map((e) => e.toEnabledString()).toList();
    } else {
      return rules.map((e) => e.toAnyString()).toList();
    }
  }

  /// To yaml object
  Object toYamlObject({bool? forceAny}) {
    if (areAllEnabled && !(forceAny ?? false)) {
      return rules.map((e) => e.name).toList();
    } else {
      var map = <String, Object>{};
      for (var rule in rules) {
        map[rule.name] = rule.enabled;
      }
      return map;
    }
  }

  /// Remove different rules
  void removeDifferentRules(Rules fromRules) {
    rules.removeWhere((element) => fromRules.rules.contains(element));
  }
}

/// Clear
class TklintListRulesCommand extends ShellBinCommand {
  /// Clear
  TklintListRulesCommand()
      : super(
            name: 'list-rules',
            parser: ArgParser(allowTrailingOptions: true),
            description: '''
List rules overrides over another file
      ''') {
    parser.addFlag('force-any', help: 'List all rules as rule: true|false');
    parser.addFlag('no-include',
        help: 'Do not handle included files', negatable: false);
    parser.addOption('from', help: 'Added from file/dep');
    parser.addFlag('from-include', help: 'Added from direct include');
  }

  @override
  FutureOr<bool> onRun() async {
    var verbose = this.verbose ?? false;
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
    var package = Package('.', verbose: verbose);
    var rules = await package.getRules(analysisOptionsPath,
        handleInclude: handleInclude, fromInclude: fromInclude);

    if (from != null) {
      var fromRules = await package.getRules(await package.resolvePath(from),
          handleInclude: true);
      rules.removeDifferentRules(fromRules);
    }
    for (var text in rules.toStringList(forceAny: forceAny)) {
      stdout.writeln(text);
    }
    return true;
  }
}

/// Package
class Package {
  /// Path
  final String path;

  /// Verbose
  final bool verbose;

  /// Config map
  late Model configMap;

  /// Create a package from a path.
  Package(this.path, {this.verbose = false});

  /// Path or package path
  Future<String> resolvePath(String pathDef) async {
    const start = 'package:';
    if (pathDef.startsWith(start)) {
      var packagePath = pathDef.substring(start.length);
      var parts = packagePath.splitFirst('/');
      var packageName = parts.first;
      var packagePathRest = parts.last;
      var ioPackagePath =
          pathPackageConfigMapGetPackagePath(path, configMap, packageName)!;
      return join(ioPackagePath, 'lib', packagePathRest);
    }
    return pathDef;
  }

  late final _initialized = () async {
    configMap = await pathGetPackageConfigMap(path);
    //print('packages: $configMap');
  }();

  /// Get rules
  Future<Rules> getRules(String path,
      {bool? handleInclude, bool? fromInclude}) async {
    await _initialized;
    handleInclude ??= false;
    fromInclude ??= false;
    var yaml = loadYaml(await File(path).readAsString()) as Map;

    Rules? includeRules;
    var rules = Rules();
    if (handleInclude) {
      var include = yaml.getKeyPathValue(['include'])?.toString();
      if (include != null) {
        var resolvedInclude = await resolvePath(include);
        if (verbose) {
          stdout.writeln('handle include: $include ($resolvedInclude)');
        }
        includeRules = await getRules(resolvedInclude, handleInclude: true);
        if (!fromInclude) {
          rules.merge(includeRules);
        }
      }
    }
    var rawRules = yaml.getKeyPathValue(['linter', 'rules']);

    if (rawRules is List) {
      for (var rawRule in rawRules) {
        if (rawRule is String) {
          rules.add(Rule(rawRule, true));
        }
      }
    } else if (rawRules is Map) {
      for (var entry in rawRules.entries) {
        var rule = entry.key as String;
        var value = entry.value;
        if (value is bool) {
          rules.add(Rule(rule, value));
        }
      }
    }
    rules.sort();
    if (fromInclude) {
      rules.removeDifferentRules(includeRules!);
    }
    return rules;
  }
}
