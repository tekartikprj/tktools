import 'dart:io';

import 'package:path/path.dart';

/// Find tekartik github top
String findGithubTop(String dirPath) {
  var dir = Directory(normalize(dirPath)).absolute;
  while (dir.path != '/') {
    if (Directory(join(dir.path, 'github.com', 'tekartik')).existsSync()) {
      return join(dir.path, 'github.com');
    }
    dir = dir.parent;
  }
  throw StateError('Cannot find top github.com dir');
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

/// Get the github path of a dependency
String getDependencyGithubPath(
    {required String githubTop, required String gitUrl}) {
  var dependencyGithubPath = Uri.parse(gitUrl).path;
  if (dependencyGithubPath.endsWith('.git')) {
    dependencyGithubPath = dependencyGithubPath.substring(
        0, dependencyGithubPath.length - '.git'.length);
  }
  if (dependencyGithubPath.startsWith('/')) {
    dependencyGithubPath = dependencyGithubPath.substring(1);
  }
  return dependencyGithubPath;
}
