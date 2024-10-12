import 'package:tekartik_prj_tktools/tkreg.dart';

/// Prefs key for the git export path
const dtkGitExportPathGlobalPrefsKey = 'com.tekartik.dtk.gitExportPath';

/// Get git export path
Future<String?> dtkGetGitExportPath() async {
  var prefs = await openGlobalPrefsPrefs();
  return prefs.getString(dtkGitExportPathGlobalPrefsKey);
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
