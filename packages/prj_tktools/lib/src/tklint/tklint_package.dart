import 'dart:convert';
import 'dart:io';

import 'package:cv/cv.dart';
import 'package:dev_build/build_support.dart';
import 'package:fs_shim/utils/io/read_write.dart';
import 'package:path/path.dart';
import 'package:tekartik_common_utils/string_utils.dart';
import 'package:tekartik_prj_tktools/yaml_edit.dart';

/// Package
class TkLintPackage {
  /// Path
  final String path;

  /// Verbose
  final bool verbose;

  /// Config map
  late Model configMap;

  /// Create a package from a path.
  TkLintPackage(this.path, {this.verbose = false});

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
  Future<TkLintRules> getIncludeRules(String path) async {
    await _initialized;
    var filePath = _fixPath(path);
    var yaml = loadYaml(await File(filePath).readAsString()) as Map;
    var include = yaml.getKeyPathValue(['include'])?.toString();
    if (include != null) {
      var resolvedInclude = await resolvePath(include);
      if (verbose) {
        stdout.writeln('handle include: $include ($resolvedInclude)');
      }
      return await getRules(resolvedInclude, handleInclude: true);
    }
    return TkLintRules();
  }

  /// Get absolute path relative to top package
  String getAbsolutePath(String path) {
    return _fixPath(path);
  }

  String _fixPath(String path) {
    if (isAbsolute(path)) {
      return path;
    }
    return join(this.path, path);
  }

  /// Get rules
  /// [handleInclude] should be true to list all the rules
  /// [fromInclude] should be true to list the real difference with the included
  Future<TkLintRules> getRules(String path,
      {bool? handleInclude, bool? fromInclude}) async {
    await _initialized;
    handleInclude ??= false;
    fromInclude ??= false;
    var analysisOptionsPath = _fixPath(path);
    late Object? yaml;
    try {
      yaml = loadYaml(await File(analysisOptionsPath).readAsString());
    } catch (e) {
      if (verbose) {
        stdout.writeln('Error reading $analysisOptionsPath: $e');
      }
      rethrow;
    }

    TkLintRules? includeRules;
    var rules = TkLintRules();

    /// yaml could be null if there is no content
    if (yaml is Map) {
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
        } else {
          if (verbose) {
            stdout.writeln('no include for $analysisOptionsPath');
          }
        }
      }
      var rawRules = yaml.getKeyPathValue(['linter', 'rules']);

      if (rawRules is List) {
        for (var rawRule in rawRules) {
          if (rawRule is String) {
            rules.add(TkLintRule(rawRule, true));
          }
        }
      } else if (rawRules is Map) {
        for (var entry in rawRules.entries) {
          var rule = entry.key as String;
          var value = entry.value;
          if (value is bool) {
            rules.add(TkLintRule(rule, value));
          }
        }
      }
      rules.sort();
      if (fromInclude && includeRules != null) {
        rules.removeDifferentRules(includeRules);
      }
    }
    return rules;
  }

  /// Write the rules if needed
  Future<void> writeRules(String path, TkLintRules rules) async {
    rules.sort();
    var filePath = _fixPath(path);
    var file = File(filePath);
    final yamlEditor = YamlEditor(await file.readAsString());
    var yamlObject = rules.toYamlObject();
    // print(yamlObject);
    yamlEditor.updateOrAdd(['linter', 'rules'], yamlObject);
    var lines = LineSplitter.split(yamlEditor.toString()).toList();
    await writeIfNeeded(path, lines);
  }

  /// Write file at path if needed
  Future<void> writeIfNeeded(String path, List<String> newLines) async {
    var filePath = _fixPath(path);
    var file = File(filePath);
    if (file.existsSync()) {
      var existing = await file.readAsLines();
      if (existing.matchesStringList(newLines)) {
        if (verbose) {
          stdout.writeln(('up to date: $filePath'));
        }
      } else {
        await writeLines(file, newLines);
        stdout.writeln(('writing...: $filePath'));
      }
    } else {
      await writeLines(file, newLines);
      stdout.writeln(('creating..: $filePath'));
    }
    return;
  }
}

/// Rule
class TkLintRule {
  /// Name
  final String name;

  /// Enabled
  final bool enabled;

  /// Rule
  TkLintRule(this.name, this.enabled);

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
    if (other is TkLintRule) {
      return (name == other.name) && (enabled == other.enabled);
    }
    return false;
  }

  @override
  String toString() => toAnyString();
}

/// Rules
class TkLintRules {
  /// Rules
  late final List<TkLintRule> rules;

  /// Rules
  TkLintRules([List<TkLintRule>? rules]) {
    this.rules = rules != null ? List.of(rules) : <TkLintRule>[];
  }

  void _removeRuleNames(List<String> ruleNames) {
    rules.removeWhere((element) => ruleNames.contains(element.name));
  }

  List<String> get _ruleNames {
    return rules.map((e) => e.name).toList();
  }

  /// Merge (rules overrides existing rules)
  void merge(TkLintRules rules) {
    _removeRuleNames(rules._ruleNames);
    this.rules.addAll(rules.rules);
  }

  /// Add a rule
  void add(TkLintRule rule) {
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
  void removeDifferentRules(TkLintRules fromRules) {
    rules.removeWhere((element) => fromRules.rules.contains(element));
  }

  static const _obsoleteRules = [
    /// Added  2024-11-25
    'unsafe_html',

    /// Added  2024-11-25
    'package_api_docs',
  ];

  /// Remove obsolete rules
  void removeObsoleteRules() {
    rules.removeWhere((element) => _obsoleteRules.contains(element.name));
  }
}
