import 'package:path/path.dart' as p;

import 'dart_import_scanner.dart';
import 'dart_run_entry.dart';

/// A [DartRunEntry] of a project, and whether it needs Flutter.
class DartRunProjectEntry {
  /// The entry.
  final DartRunEntry entry;

  /// How it reaches Flutter (see [DartImportScanner.flutterImportChain]),
  /// null when it runs on the Dart VM. For a test folder, the chain of its
  /// first test needing Flutter.
  final List<String>? flutterChain;

  /// Creates a project entry.
  const DartRunProjectEntry(this.entry, {this.flutterChain});

  /// True when it needs Flutter (`flutter run`, `flutter test`).
  bool get flutter => flutterChain != null;

  @override
  String toString() => '$entry${flutter ? ' (flutter)' : ''}';
}

/// The entries of the project at [projectPath] ([findDartRunEntries]), each
/// one telling whether it needs Flutter.
Future<List<DartRunProjectEntry>> scanDartRunEntries(String projectPath) async {
  var entries = await findDartRunEntries(projectPath);
  var scanner = DartImportScanner(projectPath);
  var chains = <String, List<String>?>{};
  for (var entry in entries) {
    if (!entry.isDirectory) {
      chains[entry.path] = await scanner.flutterImportChain(
        p.joinAll([projectPath, ...p.posix.split(entry.path)]),
      );
    }
  }
  return [
    for (var entry in entries)
      DartRunProjectEntry(
        entry,
        flutterChain: entry.isDirectory
            ? chains.entries
                  .where(
                    (file) =>
                        file.value != null &&
                        p.posix.isWithin(entry.path, file.key),
                  )
                  .firstOrNull
                  ?.value
            : chains[entry.path],
      ),
  ];
}
