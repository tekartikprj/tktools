import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:process_run/shell.dart' show Shell;

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

/// Run git with [args] in [workingDirectory] (the current one when null):
/// its result, whatever its exit code, nothing shown. It gets no input (the
/// end of it at once).
///
/// Throws when git cannot start (not found, a missing [workingDirectory]):
/// process_run's shell then says so on stderr.
Future<ProcessResult> hostCiRunGit(
  List<String> args, {
  String? workingDirectory,
}) => Shell(
  workingDirectory: workingDirectory,
  stdin: const Stream<List<int>>.empty(),
  verbose: false,
  throwOnError: false,
).runExecutableArguments('git', args);

/// Run git in [path], the trimmed stdout, null on a non zero exit code (or
/// when git cannot run).
Future<String?> hostCiGit(String path, List<String> args) async {
  // A folder gone is not worth a message of the shell.
  if (!Directory(path).existsSync()) {
    return null;
  }
  try {
    var result = await hostCiRunGit(args, workingDirectory: path);
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

/// The `git` arguments of a shallow clone of [url] in [path] ([ref]: a
/// branch or a tag, the default branch when null).
List<String> hostCiCloneArguments(String url, String path, {String? ref}) => [
  'clone',
  '--quiet',
  '--depth',
  '1',
  if (ref != null) ...['--branch', ref],
  url,
  path,
];

/// A repository link: a repository, maybe a branch and a sub folder.
///
/// From `https://github.com/dart-lang/core/tree/main/pkgs/args`,
/// `https://github.com/owner/repo(.git)`, `git@github.com:owner/repo.git`,
/// `github.com/owner/repo` or `owner/repo` (GitHub).
class HostCiRepoLink {
  /// The repository unique name (`github.com/dart-lang/core`).
  final String repoId;

  /// The url to clone (`https://github.com/dart-lang/core.git`, the ssh one
  /// when given).
  final String cloneUrl;

  /// The branch (or tag) of a `/tree/<ref>/` link, null otherwise.
  final String? ref;

  /// The sub folder of a `/tree/<ref>/<path>` link (`pkgs/args`, `/`
  /// separators), null for the whole repository.
  final String? subPath;

  /// Creates a link.
  const HostCiRepoLink({
    required this.repoId,
    required this.cloneUrl,
    this.ref,
    this.subPath,
  });

  /// The project id: [repoId], `/` [subPath] for a sub folder.
  String get projectId => subPath == null ? repoId : '$repoId/$subPath';

  /// The parts of [repoId] (`github.com`, `dart-lang`, `core`).
  List<String> get repoIdParts => repoId.split('/');

  @override
  String toString() =>
      '$cloneUrl${ref == null ? '' : ' $ref'}${subPath == null ? '' : ' $subPath'}';
}

/// True for a plain folder name of a link: not `.` nor `..`, no separator
/// (a link never points outside the checkouts folder).
bool _isPlainSegment(String segment) =>
    segment.isNotEmpty &&
    segment != '.' &&
    segment != '..' &&
    !segment.contains('/') &&
    !segment.contains(r'\');

/// The repository link of [text] (see [HostCiRepoLink]), null when it is not
/// one (a local path for example, or a `..` in it).
HostCiRepoLink? hostCiParseRepoLink(String text) {
  var link = _parseRepoLink(text);
  if (link == null ||
      !link.repoIdParts.every(_isPlainSegment) ||
      !(link.subPath?.split('/').every(_isPlainSegment) ?? true)) {
    return null;
  }
  return link;
}

HostCiRepoLink? _parseRepoLink(String text) {
  var link = text.trim();
  if (link.isEmpty) {
    return null;
  }
  // ssh: git@github.com:owner/repo.git
  if (RegExp(r'^[^@/:]+@[^:/]+:').hasMatch(link)) {
    var repoId = hostCiProjectIdFromRemoteUrl(link);
    return repoId == null
        ? null
        : HostCiRepoLink(repoId: repoId, cloneUrl: link);
  }
  String host;
  List<String> segments;
  var uri = link.contains('://') ? Uri.tryParse(link) : null;
  if (uri != null) {
    if (uri.host.isEmpty) {
      return null;
    }
    host = uri.host.toLowerCase();
    segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  } else {
    // github.com/owner/repo..., owner/repo (GitHub); not a path.
    if (link.startsWith('/') ||
        link.startsWith('.') ||
        link.startsWith('~') ||
        link.contains(r'\')) {
      return null;
    }
    var parts = link.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length < 2) {
      return null;
    }
    if (parts.first.contains('.') && parts.length >= 3) {
      host = parts.first.toLowerCase();
      segments = parts.sublist(1);
    } else if (parts.length == 2) {
      host = 'github.com';
      segments = parts;
    } else {
      return null;
    }
  }
  // owner/repo[/-]/tree/<ref>/<sub path> (GitHub, GitLab with `-`).
  var treeIndex = segments.indexOf('tree');
  var repoSegments = treeIndex < 0 ? segments : segments.sublist(0, treeIndex);
  if (repoSegments.isNotEmpty && repoSegments.last == '-') {
    repoSegments = repoSegments.sublist(0, repoSegments.length - 1);
  }
  if (repoSegments.length < 2) {
    return null;
  }
  var repo = repoSegments.last;
  if (repo.endsWith('.git')) {
    repo = repo.substring(0, repo.length - 4);
  }
  if (repo.isEmpty) {
    return null;
  }
  var ownerPath = repoSegments.sublist(0, repoSegments.length - 1).join('/');
  String? ref;
  String? subPath;
  if (treeIndex >= 0 && treeIndex + 1 < segments.length) {
    ref = segments[treeIndex + 1];
    var sub = segments.sublist(treeIndex + 2);
    if (sub.isNotEmpty) {
      subPath = sub.join('/');
    }
  }
  return HostCiRepoLink(
    repoId: '$host/$ownerPath/$repo',
    cloneUrl: 'https://$host/$ownerPath/$repo.git',
    ref: ref,
    subPath: subPath,
  );
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
