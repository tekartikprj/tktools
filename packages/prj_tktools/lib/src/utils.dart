import 'dart:io';

import 'package:path/path.dart';
import 'package:tekartik_common_utils/string_utils.dart';
import 'package:tekartik_prj_tktools/src/tkpub_db.dart';

/// Find tekartik github top
Future<String> tkPubFindGithubTop({String? dirPath}) async {
  if (dirPath != null) {
    var dir = _findGithubTopOrNull(dirPath);
    if (dir != null) {
      return dir;
    }
  }
  var dir = _findGithubTopOrNull(Directory.current.path);
  if (dir != null) {
    return dir;
  }
  var prefs = await openPrefs();
  var prefsPath = prefs.getString(prefsKeyConfigExportPath);
  if (prefsPath != null) {
    var dir = _findGithubTopOrNull(prefsPath);
    if (dir != null) {
      return dir;
    }
  }
  throw StateError('Cannot find top github.com dir');
}

/// Find tekartik github top
String findGithubTop(String dirPath) {
  var dir = _findGithubTopOrNull(dirPath);
  if (dir != null) {
    return dir;
  }
  throw StateError('Cannot find top github.com dir');
}

/// Find tekartik github top
String? _findGithubTopOrNull(String dirPath) {
  var dir = Directory(normalize(dirPath)).absolute;
  while (dir.path != '/') {
    if (Directory(join(dir.path, 'github.com', 'tekartik')).existsSync()) {
      return join(dir.path, 'github.com');
    }
    dir = dir.parent;
  }
  return null;
}

/// Get the local path of a dependency (absolute)
String getDependencyLocalPath(
    {required String githubTop, required String gitUrl, String? gitPath}) {
  var dependencyGithubPath =
      getDependencyGithubPath(githubTop: githubTop, gitUrl: gitUrl);
  var dependencyPath = normalize(absolute(joinAll([
    githubTop,
    dependencyGithubPath,
    if (gitPath?.isNotEmpty ?? false) gitPath!
  ])));

  return dependencyPath;
}

/// Find the path of a url
String safeGetUrlPath(String url) {
  var uri = Uri.tryParse(url);
  if (uri != null) {
    return uri.path;
  }
  // git like uri?
  if (url.startsWith('git@')) {
    var path = url.splitFirst(':')[1];
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    return path;
  }
  throw ArgumentError('Unsupported url $url');
}

/// Get the github path of a dependency
String getDependencyGithubPath(
    {required String githubTop, required String gitUrl}) {
  var dependencyGithubPath = safeGetUrlPath(gitUrl);
  if (dependencyGithubPath.endsWith('.git')) {
    dependencyGithubPath = dependencyGithubPath.substring(
        0, dependencyGithubPath.length - '.git'.length);
  }
  if (dependencyGithubPath.startsWith('/')) {
    dependencyGithubPath = dependencyGithubPath.substring(1);
  }
  return dependencyGithubPath;
}

/// Safe yaml string
String safeYamlString(Object? object) {
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
