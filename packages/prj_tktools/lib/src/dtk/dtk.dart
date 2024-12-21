import 'dart:io';

import 'package:fs_shim/utils/io/read_write.dart';
import 'package:tekartik_common_utils/string_utils.dart';
import 'package:tekartik_prj_tktools/tkreg.dart';

/// Prefs key for the git export path
const dtkGitExportPathGlobalPrefsKey = 'com.tekartik.dtk.gitExportPath';

/// Prefs key for the dep export path
const dtkDepExportPathGlobalPrefsKey = 'com.tekartik.dtk.depExportPath';

/// common extension
extension DtkFileExt on File {
  /// Write file at path if needed
  Future<void> writeLinesIfNeeded(List<String> newLines,
      {bool? verbose, bool? verboseIfNeeded}) async {
    verbose ??= false;
    verboseIfNeeded ??= false;
    var file = this;
    if (file.existsSync()) {
      var existing = await file.readAsLines();
      if (existing.matchesStringList(newLines)) {
        if (verbose) {
          stdout.writeln(('up to date: $path'));
        }
      } else {
        await file.writeLines(newLines);
        if (verbose || verboseIfNeeded) {
          stdout.writeln(('writing...: $path'));
        }
      }
    } else {
      await writeLines(file, newLines);
      if (verbose || verboseIfNeeded) {
        stdout.writeln(('creating..: $path'));
      }
    }
    return;
  }
}

/// Get git export path
Future<String?> dtkGetGitExportPath() async {
  var prefs = await openGlobalPrefsPrefs();
  var path = prefs.getString(dtkGitExportPathGlobalPrefsKey);
  return path;
}

/// Get dep export path
Future<String?> dtkGetDepExportPath() async {
  var prefs = await openGlobalPrefsPrefs();
  var path = prefs.getString(dtkDepExportPathGlobalPrefsKey);
  return path;
}

/// Get git unique name from url
class DtkGitRepositoryRef {
  /// Example github.com
  late final String host;

  /// Example tekartik/app_common_utils.dart
  late final String path;

  /// Constructor
  DtkGitRepositoryRef({required this.host, required this.path});

  /// Constructor from url
  DtkGitRepositoryRef.fromUrl(String gitUrl) {
    List<String> parts;
    String host;
    if (gitUrl.startsWith('git@')) {
      parts = gitUrl.split('/');
      var startParts = parts.first.split(':');
      host = startParts[0].split('@').last;
      parts = [...startParts.sublist(1), ...parts.sublist(1)];
    } else {
      var uri = Uri.parse(gitUrl);
      host = uri.host;
      parts = uri.path.split('/');
    }

    /// remove trailing .git
    var repoName = parts.last;
    if (repoName.endsWith('.git')) {
      repoName = repoName.substring(0, repoName.length - 4);
    }

    var pathParts = parts.sublist(0, parts.length - 1).toList();
    if (pathParts[0] == '/' || pathParts[0].isEmpty) {
      pathParts = pathParts.sublist(1);
    }

    this.host = host;
    path = [...pathParts, repoName].join('/');
  }

  /// Get unique name
  String get uniqueName => '$host/$path';

  @override
  String toString() => uniqueName;
}

/// Get git unique name from url
String dtkGitUniqueNameFromUrl(String url) {
  return DtkGitRepositoryRef.fromUrl(url).uniqueName;
}
