import 'package:cv/cv.dart';
import 'package:dev_build/package.dart';
import 'package:fs_shim/utils/io/read_write.dart';
import 'package:path/path.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_common_utils/json_utils.dart';
import 'package:tekartik_prj_tktools/yaml_edit.dart';

int _compareKeys(String key1, String key2) {
  if (key1.startsWith('@@')) {
    if (key2.startsWith('@@')) {
      return key1.compareTo(key2);
    }
    return -1;
  } else if (key2.startsWith('@@')) {
    return 1;
  }
  if (key1.startsWith('@')) {
    if (key2.startsWith('@')) {
      return key1.compareTo(key2);
    }
    var cmp = _compareKeys(key1.substring(1), key2);
    if (cmp == 0) {
      return 1;
    }
    return cmp;
  } else {
    if (key2.startsWith('@')) {
      return -_compareKeys(key2, key1);
    }
    return key1.compareTo(key2);
  }
}

/// Formats arb files in the lib/l10n directory
Future<void> arbFormat({String? path, bool? verbose}) async {
  verbose ??= false;
  await recursivePackagesRun(
    [path ?? '.'],
    action: (path) async {
      stdout.writeln('Running ${absolute(path)}');
      var l10nDir = Directory(join(path, 'lib', 'l10n'));
      var l10nFile = File(join(path, 'l10n.yaml'));
      if (l10nFile.existsSync()) {
        var l10Map = loadYaml(l10nFile.readAsStringSync()) as Map;
        var arbDir = l10Map['arb-dir'] as String?;
        if (arbDir != null) {
          l10nDir = Directory(join(path, arbDir));
        }
      }
      // print('Looking for l10n dir at ${l10nDir.path}');
      if (l10nDir.existsSync()) {
        await for (var file in l10nDir.list()) {
          if (file is File && extension(file.path) == '.arb') {
            if (verbose!) {
              stderr.writeln('Reading $file');
            }
            var textContext = file.readAsStringSync();
            var content = parseJsonObject(file.readAsStringSync())!;
            var keys = content.keys.toList();

            keys.sort(_compareKeys);
            var map = newModel();
            for (var key in keys) {
              map[key] = content[key];
            }

            var newTextContext = stringToIoString(jsonPretty(map)!);
            if (textContext != newTextContext) {
              stderr.writeln('Writing $file');
              file.writeAsStringSync(stringToIoString(jsonPretty(map)!));
            }
          }
        }
      } else {
        stderr.writeln('No l10n dir found in $path');
      }
    },
  );
}

/// Sort arb map keys
Model arbMapFormat(Model arbMap) {
  var keys = arbSortedKeys(arbMap.keys);
  var map = newModel();
  for (var key in keys) {
    map[key] = arbMap[key];
  }
  return map;
}

/// Sort keys
List<String> arbSortedKeys(Iterable<String> keys) {
  var sortedKeys = List<String>.of(keys);
  sortedKeys.sort(_compareKeys);
  return sortedKeys;
}
