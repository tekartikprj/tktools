import 'package:args/args.dart';
import 'package:cv/cv.dart';
import 'package:dev_build/build_support.dart';
import 'package:path/path.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_common_utils/string_utils.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:yaml/yaml.dart';

class _Rule {
  final String name;
  final bool enabled;

  _Rule(this.name, this.enabled);

  String toAnyString() {
    return '$name: $enabled';
  }

  String toEnabledString() {
    return '- $name';
  }

  @override
  int get hashCode => name.hashCode;
  @override
  bool operator ==(Object other) {
    if (other is _Rule) {
      return (name == other.name) && (enabled == other.enabled);
    }
    return false;
  }

  @override
  String toString() => toAnyString();
}

class _Rules {
  late final List<_Rule> rules;

  _Rules([List<_Rule>? rules]) {
    this.rules = rules != null ? List.of(rules) : <_Rule>[];
  }

  void removeRuleNames(List<String> ruleNames) {
    rules.removeWhere((element) => ruleNames.contains(element.name));
  }

  List<String> get ruleNames {
    return rules.map((e) => e.name).toList();
  }

  void merge(_Rules rules) {
    removeRuleNames(rules.ruleNames);
    this.rules.addAll(rules.rules);
  }

  void add(_Rule rule) {
    rules.removeWhere((element) => element.name == rule.name);
    rules.add(rule);
  }

  void sort() {
    rules.sort((a, b) => a.name.compareTo(b.name));
  }

  bool get areAllEnabled {
    for (var rule in rules) {
      if (!rule.enabled) {
        return false;
      }
    }
    return true;
  }

  bool isEnabled(String name) {
    for (var rule in rules) {
      if (rule.name == name) {
        return rule.enabled;
      }
    }
    return false;
  }

  List<String> toStringList({bool? forceAny}) {
    if (areAllEnabled && !(forceAny ?? false)) {
      return rules.map((e) => e.toEnabledString()).toList();
    } else {
      return rules.map((e) => e.toAnyString()).toList();
    }
  }

  void removeDifferentRules(_Rules fromRules) {
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
    var package = _Package('.', verbose: verbose);
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

class _Package {
  final String path;
  final bool verbose;

  late Model configMap;
  _Package(this.path, {this.verbose = false});

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
  Future<_Rules> getRules(String path,
      {bool? handleInclude, bool? fromInclude}) async {
    await _initialized;
    handleInclude ??= false;
    fromInclude ??= false;
    var yaml = loadYaml(await File(path).readAsString()) as Map;

    _Rules? includeRules;
    var rules = _Rules();
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
          rules.add(_Rule(rawRule, true));
        }
      }
    } else if (rawRules is Map) {
      for (var entry in rawRules.entries) {
        var rule = entry.key as String;
        var value = entry.value;
        if (value is bool) {
          rules.add(_Rule(rule, value));
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
