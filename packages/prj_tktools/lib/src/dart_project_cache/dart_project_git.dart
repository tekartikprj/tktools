import 'package:path/path.dart' as p;

import 'dart_project.dart';

/// The url of the `origin` remote of a git [config] file content, the first
/// remote when none is named `origin`, null when there is none.
String? gitConfigRemoteUrl(String config) {
  String? section;
  String? first;
  for (var rawLine in config.split('\n')) {
    var line = rawLine.trim();
    if (line.startsWith('[')) {
      section = line;
      continue;
    }
    if (section == null || !section.startsWith('[remote ')) {
      continue;
    }
    var match = RegExp(r'^url\s*=\s*(.+)$').firstMatch(line);
    if (match == null) {
      continue;
    }
    var url = match.group(1)!.trim();
    if (section == '[remote "origin"]') {
      return url;
    }
    first ??= url;
  }
  return first;
}

/// The hosts whose repositories can be opened on the web, see [gitWebUri].
const gitWebHosts = {'github.com', 'gitlab.com', 'bitbucket.org'};

/// The web page of the git [remote] (`https://github.com/owner/repo`), and
/// of its folder [subPath] (posix, relative to the repository), null when
/// the remote is not on a known host ([gitWebHosts]).
///
/// Handles the https (`https://github.com/owner/repo.git`), ssh
/// (`ssh://git@github.com/owner/repo`) and scp like
/// (`git@github.com:owner/repo.git`) remotes, and the ssh host aliases of a
/// known host (`github.com-account`, one ssh key per account). A sub folder
/// is displayed on the default branch (`HEAD`).
Uri? gitWebUri(String remote, {String? subPath}) {
  String? host;
  String? repoPath;
  var scp = RegExp(r'^(?:[\w.-]+@)?([\w.-]+):(?!//)(.+)$').firstMatch(remote);
  if (scp != null) {
    host = scp.group(1);
    repoPath = scp.group(2);
  } else {
    var uri = Uri.tryParse(remote);
    if (uri != null && uri.host.isNotEmpty) {
      host = uri.host;
      repoPath = uri.path;
    }
  }
  if (host == null || repoPath == null) {
    return null;
  }
  if (!gitWebHosts.contains(host)) {
    // An ssh host alias.
    host = gitWebHosts
        .where((webHost) => host!.startsWith('$webHost-'))
        .firstOrNull;
    if (host == null) {
      return null;
    }
  }
  var segments = repoPath
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.length < 2) {
    return null;
  }
  var repo = segments.last;
  if (repo.endsWith('.git')) {
    segments.last = repo.substring(0, repo.length - '.git'.length);
  }
  var sub = subPath == null ? '' : p.posix.normalize(subPath);
  if (sub.isNotEmpty && sub != '.') {
    var tree = switch (host) {
      'gitlab.com' => ['-', 'tree', 'HEAD'],
      'bitbucket.org' => ['src', 'HEAD'],
      _ => ['tree', 'HEAD'],
    };
    segments.addAll([...tree, ...sub.split('/')]);
  }
  return Uri(scheme: 'https', host: host, pathSegments: segments);
}

/// The site name of a [gitWebUri] (`GitHub`...).
String gitWebSiteName(Uri uri) => switch (uri.host) {
  'github.com' => 'GitHub',
  'gitlab.com' => 'GitLab',
  'bitbucket.org' => 'Bitbucket',
  _ => uri.host,
};

/// The web page of the folder [path] of the repository [git] (its root
/// included), null when its remote is not on a known host.
///
/// [context] is the path context of the cache (the io one by default).
Uri? dartProjectGitWebUri(
  DartProjectGitFolderInfo git,
  String path, {
  p.Context? context,
}) {
  var remote = git.remote;
  if (remote == null) {
    return null;
  }
  context ??= p.context;
  var subPath = path == git.path
      ? null
      : p.posix.joinAll(context.split(context.relative(path, from: git.path)));
  return gitWebUri(remote, subPath: subPath);
}
