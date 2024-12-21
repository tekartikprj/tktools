import 'dart:convert';

import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

class _NoYamlNode implements YamlNode {
  const _NoYamlNode();
  @override
  SourceSpan get span => throw UnimplementedError();

  @override
  Object? get value => null;

  @override
  int get hashCode => 0;

  @override
  bool operator ==(Object other) {
    return identical(this, _noYamlNode);
  }
}

const _noYamlNode = _NoYamlNode();

extension on Object? {
  bool get isEmpty {
    var self = this;
    if (self == null) {
      return true;
    } else if (self == _noYamlNode) {
      return true;
    } else if (self is String) {
      return self.isEmpty;
    } else if (self is List) {
      return self.isEmpty;
    } else if (self is Map) {
      return self.isEmpty;
    }
    return false;
  }
}

/// Yaml editor extension
extension TekartikYamlEditorExt on YamlEditor {
  /// Export current result as lines
  List<String> toLines() => LineSplitter.split(toString()).toList();

  /// Update or add a value at a given path
  void updateOrAdd(List<Object> path, Object? value, {int? index}) {
    var existing = parseAt(path, orElse: () => _noYamlNode);
    if (!identical(existing, _noYamlNode)) {
      if (value.isEmpty && existing.isEmpty) {
        return;
      }
      update(path, value);
    } else {
      if (value.isEmpty) {
        return;
      }
      var key = path.last as String;
      var nextPath = path.sublist(0, path.length - 1);
      if (nextPath.isEmpty) {
        // root
        update(path, value);
      } else {
        var nextValue = <String, Object?>{key: value};

        existing = parseAt(nextPath, orElse: () => _noYamlNode);
        if (!identical(existing, _noYamlNode)) {
          if (existing is YamlMap) {
            update(path, value);
            return;
          }
        }
        updateOrAdd(nextPath, nextValue);
      }
    }
  }
}
