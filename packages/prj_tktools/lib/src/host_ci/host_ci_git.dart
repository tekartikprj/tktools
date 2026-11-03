import 'dart:io';

import 'package:path/path.dart' as p;

/// What git says about a checkout before a run, no network unless fetched.
class HostCiGitFacts {
  /// HEAD sha.
  final String head;

  /// Branch name, null when detached.
  final String? branch;

  /// Commit time of HEAD.
  final DateTime? commitTime;

  /// Number of `git status --porcelain` lines, 0 when clean.
  final int dirty;

  /// Commits ahead of the upstream, null without upstream.
  final int? ahead;

  /// Commits behind the upstream, null without upstream or when not fetched.
  final int? behind;

  /// Creates the facts.
  HostCiGitFacts({
    required this.head,
    this.branch,
    this.commitTime,
    required this.dirty,
    this.ahead,
    this.behind,
  });

  /// True when the tree has no modified file.
  bool get isClean => dirty == 0;

  /// Short sha (7 characters).
  String get shortHead => head.length > 7 ? head.substring(0, 7) : head;

  @override
  String toString() =>
      '$shortHead${branch == null ? '' : ' $branch'} dirty $dirty'
      '${ahead == null ? '' : ' ahead $ahead'}'
      '${behind == null ? '' : ' behind $behind'}';
}

/// True when [path] is a git checkout (a `.git` directory or file).
bool hostCiIsGitCheckout(String path) {
  var gitPath = p.join(path, '.git');
  return Directory(gitPath).existsSync() || File(gitPath).existsSync();
}

/// Run git in [path], the trimmed stdout, null on a non zero exit code (or
/// when git cannot run).
Future<String?> hostCiGit(String path, List<String> args) async {
  try {
    var result = await Process.run('git', args, workingDirectory: path);
    if (result.exitCode != 0) {
      return null;
    }
    return (result.stdout as String).trim();
  } catch (_) {
    return null;
  }
}

/// Read the git facts of the checkout at [path], null when it is not a git
/// checkout (or git fails).
///
/// With [fetch], `git fetch --quiet` runs first (network) and [HostCiGitFacts.behind]
/// is known.
Future<HostCiGitFacts?> hostCiReadGitFacts(
  String path, {
  bool fetch = false,
}) async {
  if (!hostCiIsGitCheckout(path)) {
    return null;
  }
  if (fetch) {
    await hostCiGit(path, ['fetch', '--quiet']);
  }
  var head = await hostCiGit(path, ['rev-parse', 'HEAD']);
  if (head == null || head.isEmpty) {
    return null;
  }
  var branch = await hostCiGit(path, ['rev-parse', '--abbrev-ref', 'HEAD']);
  if (branch == 'HEAD') {
    branch = null;
  }
  var commitSeconds = int.tryParse(
    await hostCiGit(path, ['log', '-1', '--format=%ct']) ?? '',
  );
  var status = await hostCiGit(path, ['status', '--porcelain']);
  var dirty = status == null || status.isEmpty
      ? 0
      : status.split('\n').where((line) => line.isNotEmpty).length;
  var ahead = int.tryParse(
    await hostCiGit(path, ['rev-list', '--count', '@{u}..HEAD']) ?? '',
  );
  int? behind;
  if (fetch && ahead != null) {
    behind = int.tryParse(
      await hostCiGit(path, ['rev-list', '--count', 'HEAD..@{u}']) ?? '',
    );
  }
  return HostCiGitFacts(
    head: head,
    branch: branch,
    commitTime: commitSeconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(commitSeconds * 1000),
    dirty: dirty,
    ahead: ahead,
    behind: behind,
  );
}

/// How many commits [to] is after [from] (`from..to`), null when [from] is
/// unknown to the repository (rewritten history, shallow clone).
Future<int?> hostCiCountCommits(String path, String from, String to) async {
  var count = await hostCiGit(path, ['rev-list', '--count', '$from..$to']);
  return int.tryParse(count ?? '');
}

/// The `origin` remote url of the checkout at [path], null when none.
Future<String?> hostCiGitRemoteUrl(String path) async {
  var url = await hostCiGit(path, ['config', '--get', 'remote.origin.url']);
  return (url == null || url.isEmpty) ? null : url;
}

/// The repository unique name of a remote url (`github.com/owner/repo`), the
/// dtk way, null when the url is not understood.
///
/// `git@github.com:owner/repo.git`, `https://github.com/owner/repo.git`,
/// `ssh://git@github.com/owner/repo` all give `github.com/owner/repo`.
String? hostCiProjectIdFromRemoteUrl(String url) {
  var text = url.trim();
  if (text.isEmpty) {
    return null;
  }
  String? host;
  String? repoPath;
  var scp = RegExp(r'^[^@/:]+@([^:/]+):(.+)$').firstMatch(text);
  if (scp != null) {
    host = scp.group(1);
    repoPath = scp.group(2);
  } else {
    var uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    host = uri.host;
    repoPath = uri.path;
  }
  var segments = repoPath!
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.length < 2) {
    return null;
  }
  var repo = segments.last;
  if (repo.endsWith('.git')) {
    repo = repo.substring(0, repo.length - 4);
  }
  if (repo.isEmpty) {
    return null;
  }
  return [
    host!.toLowerCase(),
    ...segments.sublist(0, segments.length - 1),
    repo,
  ].join('/');
}

/// The project id of the checkout at [path]: the unique name of its remote,
/// the canonical path when it has none.
Future<String> hostCiProjectIdForPath(String path) async {
  var url = await hostCiGitRemoteUrl(path);
  var id = url == null ? null : hostCiProjectIdFromRemoteUrl(url);
  return id ?? hostCiCanonicalPath(path);
}

/// Canonical absolute path.
String hostCiCanonicalPath(String path) => p.normalize(p.absolute(path));

/// True when the checkout at [path] has a GitHub workflow file
/// (`.github/workflows/*.yml`).
bool hostCiHasCiWorkflow(String path) {
  var dir = Directory(p.join(path, '.github', 'workflows'));
  if (!dir.existsSync()) {
    return false;
  }
  try {
    return dir
        .listSync(followLinks: false)
        .any(
          (entity) =>
              entity is File &&
              (entity.path.endsWith('.yml') || entity.path.endsWith('.yaml')),
        );
  } catch (_) {
    return false;
  }
}
