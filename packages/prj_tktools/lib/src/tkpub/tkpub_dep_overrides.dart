import 'dart:io';
import 'package:path/path.dart';
import 'package:yaml/yaml.dart';

/// Helper to manage pubspec_overrides.yaml changes.
class TkPubDepOverrides {
  /// The root path of the project.
  final String rootPath;

  /// Creates a new [TkPubDepOverrides] instance for the project at [rootPath].
  TkPubDepOverrides({required this.rootPath});

  /// The `pubspec_overrides.yaml` file.
  File get overridesFile => File(join(rootPath, 'pubspec_overrides.yaml'));

  /// The `.pubspec_overrides.yaml` file (disabled version).
  File get disabledOverridesFile =>
      File(join(rootPath, '.pubspec_overrides.yaml'));

  /// Returns true if overrides file exists.
  bool get exists => overridesFile.existsSync();

  /// Returns true if disabled overrides file exists.
  bool get disabledExists => disabledOverridesFile.existsSync();

  /// Read the current dependency overrides as a Map.
  /// Returns empty map if file doesn't exist or is invalid.
  Future<Map<String, dynamic>> readOverrides() async {
    if (!exists) return <String, dynamic>{};
    try {
      var content = await overridesFile.readAsString();
      var loaded = loadYaml(content);
      if (loaded is Map) {
        var dependencyOverrides = loaded['dependency_overrides'];
        if (dependencyOverrides is Map) {
          return Map<String, dynamic>.from(dependencyOverrides);
        }
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  /// Write dependency overrides.
  /// If [overridesMap] is empty, deletes the overrides file.
  Future<void> writeOverrides(Map<String, dynamic> overridesMap) async {
    if (overridesMap.isEmpty) {
      if (exists) {
        await overridesFile.delete();
      }
      return;
    }

    Map? doc;
    if (exists) {
      try {
        var content = await overridesFile.readAsString();
        var loaded = loadYaml(content);
        if (loaded is Map) {
          doc = loaded;
        }
      } catch (_) {}
    }

    var docMap = doc != null
        ? Map<String, dynamic>.from(doc)
        : <String, dynamic>{};
    docMap['dependency_overrides'] = overridesMap;

    var newYamlText = mapToYaml(docMap);
    await overridesFile.parent.create(recursive: true);
    await overridesFile.writeAsString(newYamlText);
  }

  /// Disable overrides by renaming pubspec_overrides.yaml to .pubspec_overrides.yaml
  Future<bool> disable({bool verbose = false}) async {
    if (exists) {
      if (disabledExists) {
        if (verbose) {
          stdout.writeln(
            'Removing existing disabled overrides file: ${disabledOverridesFile.path}',
          );
        }
        try {
          await disabledOverridesFile.delete();
        } catch (e) {
          stderr.writeln(
            'Error: Failed to delete existing ${disabledOverridesFile.path}: $e',
          );
          return false;
        }
      }
      try {
        await overridesFile.rename(disabledOverridesFile.path);
        stdout.writeln(
          'Disabled overrides: renamed ${overridesFile.path} to ${disabledOverridesFile.path}',
        );
      } catch (e) {
        stderr.writeln('Error: Failed to rename overrides file: $e');
        return false;
      }
      return true;
    } else {
      if (verbose) {
        stdout.writeln(
          'No pubspec_overrides.yaml found to disable at $rootPath',
        );
      }
      return true;
    }
  }

  /// Helper to serialize map to standard block style YAML string.
  static String mapToYaml(Map map) {
    var lines = <String>[];
    _mapToYamlLines(map, '', lines);
    return '${lines.join('\n')}\n';
  }

  static void _mapToYamlLines(Map map, String indent, List<String> lines) {
    var sorted = _sortMap(map);
    for (var key in sorted.keys) {
      var value = sorted[key];
      if (value is Map) {
        if (value.isEmpty) {
          lines.add('$indent$key: {}');
        } else {
          lines.add('$indent$key:');
          _mapToYamlLines(value, '$indent  ', lines);
        }
      } else {
        lines.add('$indent$key: ${_safeYamlString(value)}');
      }
    }
  }

  static Map<String, dynamic> _sortMap(Map map) {
    var sorted = <String, dynamic>{};
    var keys = map.keys.map((k) => k.toString()).toList()..sort();
    for (var key in keys) {
      var value = map[key];
      if (value is Map) {
        sorted[key] = _sortMap(value);
      } else {
        sorted[key] = value;
      }
    }
    return sorted;
  }

  static String _safeYamlString(Object? object) {
    if (object == null) {
      return '';
    }
    var value = object.toString();
    if (value.contains(RegExp(r'[":]'))) {
      return "'$value'";
    }
    if (value.contains(RegExp(r'[\\]')) || value.startsWith('>')) {
      return '"$value"';
    }
    return value;
  }
}
