import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:cv/cv.dart';

/// Pubspec target
enum TkpubTarget {
  /// dev: target
  dev,

  /// override: target
  override,

  /// pubspec_overrides: (pubspec_overrides.yaml file)
  pubspecOverrides
}

/// Convert target to string
String tkpubTargetToString(TkpubTarget target) {
  switch (target) {
    case TkpubTarget.dev:
      return 'dev';
    case TkpubTarget.override:
      return 'override';
    case TkpubTarget.pubspecOverrides:
      return 'pubspec_overrides';
  }
}

/// Package info for tkpub add
class TkpubPackageInfo {
  /// def as a map.
  final Model? def;

  /// Package name
  final String name;

  /// Target
  final TkpubTarget? target;

  /// Package info
  TkpubPackageInfo({this.def, required this.name, this.target});

  /// Parse and argument like
  /// - test
  /// - dev:test
  /// - test:{"path":"../test"}
  static TkpubPackageInfo parse(String arg) {
    arg = arg.trim();
    if (arg.startsWith("'") && arg.endsWith("'")) {
      arg = arg.substring(1, arg.length - 1);
    }
    var parts = arg.split(':');
    Model? def;
    String name;
    TkpubTarget? target;

    bool isDef(String part) {
      return part.startsWith('{');
    }

    TkpubTarget getTarget(int partIndex) {
      var part = parts[partIndex].trim();
      switch (part) {
        case 'dev':
          return TkpubTarget.dev;
        case 'override':
          return TkpubTarget.override;
        case 'pubspec_overrides':
          return TkpubTarget.pubspecOverrides;
      }
      throw 'Invalid target: $part';
    }

    String getName(int partIndex) {
      return parts[partIndex].trim();
    }

    Model getDef(int partIndex) {
      var start = 0;
      for (var i = 0; i < partIndex; i++) {
        start += parts[i].length + 1;
      }
      return asModel(jsonDecode(arg.substring(start).trim()) as Map);
    }

    if (parts.length == 1) {
      name = getName(0);
    } else if (parts.length == 2) {
      if (isDef(parts[1])) {
        name = getName(0);
        def = getDef(1);
      } else {
        target = getTarget(0);
        name = getName(1);
      }
    } else {
      /// : might be part of the def so test 2 arg scenario again
      if (isDef(parts[1])) {
        name = getName(0);
        def = getDef(1);
      } else if (isDef(parts[2])) {
        target = getTarget(0);
        name = getName(1);
        def = getDef(2);
      } else {
        throw ArgumentError('Invalid arg: $arg');
      }
    }

    return TkpubPackageInfo(def: def, name: name, target: target);
  }

  @override
  bool operator ==(Object other) {
    if (other is TkpubPackageInfo) {
      if (target == other.target &&
          name == other.name &&
          const DeepCollectionEquality().equals(def, other.def)) {
        return true;
      }
    }
    return false;
  }

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    var sb = StringBuffer();
    if (target != null) {
      sb.write('${tkpubTargetToString(target!)}:');
    }
    sb.write(name);
    if (def != null) {
      sb.write(':${jsonEncode(def)}');
    }
    return sb.toString();
  }
}
