import 'package:dev_build/package.dart';
import 'package:dev_build/shell.dart';
import 'package:path/path.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_prj_tktools/yaml_edit.dart';

/// Returns the l10n directory based on l10n.yaml if present
Directory arbL10nDirectory(String path) {
  var l10nDir = Directory(join(path, 'lib', 'l10n'));
  var l10nFile = File(join(path, 'l10n.yaml'));
  if (l10nFile.existsSync()) {
    var l10Map = loadYaml(l10nFile.readAsStringSync()) as Map;
    var arbDir = l10Map['arb-dir'] as String?;
    if (arbDir != null) {
      l10nDir = Directory(join(path, arbDir));
    }
  }
  return l10nDir;
}

/// Formats arb files in the lib/l10n directory
Future<void> arbRecursive({
  String? path,
  bool? verbose,
  required Future<void> Function(String path) action,
}) async {
  verbose ??= false;
  await recursivePackagesRun(
    [path ?? '.'],
    action: (path) async {
      stdout.writeln('Running ${absolute(path)}');
      var l10nDir = arbL10nDirectory(path);
      // print('Looking for l10n dir at ${l10nDir.path}');
      if (l10nDir.existsSync()) {
        await action(path);
      } else {
        if (verbose!) {
          stderr.writeln('No l10n dir found in $path');
        }
      }
    },
  );
}

/// Formats arb files in the lib/l10n directory
Future<void> arbGenerateIntl({String? path, bool? verbose}) async {
  verbose ??= false;
  await arbRecursive(
    path: path,
    verbose: verbose,
    action: (path) async {
      var l10nDir = arbL10nDirectory(path);
      if (l10nDir.existsSync()) {
        await Shell(workingDirectory: path).run('flutter gen-l10n');
      } else {
        if (verbose!) {
          stderr.writeln('No l10n dir found in $path');
        }
      }
    },
  );
}
