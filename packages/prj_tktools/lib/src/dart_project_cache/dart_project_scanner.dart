import 'package:dev_build/build_support.dart'
    show
        pubspecYamlGetPackageName,
        pubspecYamlGetSdkBoundaries,
        pubspecYamlHasWorkspaceResolution,
        pubspecYamlIsWorkspaceRoot,
        pubspecYamlSupportsFlutter;
import 'package:fs_shim/fs_shim.dart';
import 'package:process_run/shell.dart' show dartVersion;
import 'package:yaml/yaml.dart';

import 'dart_project.dart';
import 'dart_project_git.dart';

const _pubspecYaml = 'pubspec.yaml';
const _localWorkspaceJson = 'local_workspace.json';
const _dotGit = '.git';

/// Folders never scanned, like `iteratePubPath` of `dev_build` (the hidden
/// ones too).
const _ignoredFolderNames = {'build', 'deploy', 'node_modules'};

/// Top folders of a project never scanned, test fixtures can hold a
/// `pubspec.yaml` file.
const _ignoredProjectFolderNames = {'test'};

/// What a scan found.
class DartProjectScanResult {
  /// Canonical path of the folder scanned.
  final String path;

  /// The projects (and local workspaces) found, sorted by path once the scan
  /// is done.
  final List<DartProjectInfo> projects;

  /// The git repositories found, sorted by path once the scan is done.
  final List<DartProjectGitFolderInfo> gitFolders;

  /// The folders that could not be read, empty when all good.
  final List<String> errors;

  /// True when the scan was cancelled, [projects] is then what was found
  /// before it stopped.
  final bool cancelled;

  /// When the scan started, the refresh time of every project found.
  final DateTime refreshed;

  /// Creates a scan result.
  const DartProjectScanResult({
    required this.path,
    required this.projects,
    required this.errors,
    required this.refreshed,
    this.gitFolders = const [],
    this.cancelled = false,
  });

  /// The same result, with more [errors].
  DartProjectScanResult withErrors(List<String> errors) =>
      DartProjectScanResult(
        path: path,
        projects: projects,
        gitFolders: gitFolders,
        errors: [...this.errors, ...errors],
        refreshed: refreshed,
        cancelled: cancelled,
      );

  @override
  String toString() =>
      '$path: ${projects.length} projects'
      '${errors.isEmpty ? '' : ', ${errors.length} errors'}'
      '${cancelled ? ' (cancelled)' : ''}';
}

/// Scans a folder tree for dart projects, on any file system.
///
/// A dart project is a folder holding a `pubspec.yaml` supporting the current
/// dart sdk, like `iteratePubPath` of `dev_build`: the hidden folders,
/// `build`, `deploy`, `node_modules` and the `test` folder of a project are
/// not scanned. The links are not followed.
///
/// A folder holding a `local_workspace.json` file is a local workspace, a
/// folder with a `.git` entry is a git repository (its remote is read).
///
/// A pub workspace root is a flutter workspace when one of its packages
/// (`resolution: workspace`) found below it is a flutter one.
class DartProjectScanner {
  /// The file system scanned.
  final FileSystem fs;

  /// Canonical path of the folder to scan.
  final String path;

  /// Called with what was found so far, every time a project is found (at
  /// most once per [progressInterval] when set).
  final void Function(DartProjectScanResult found)? onProgress;

  /// The minimum time between 2 [onProgress] calls, every project found is
  /// reported when null.
  final Duration? progressInterval;

  var _cancelled = false;
  Stopwatch? _sinceProgress;

  /// Creates a scanner of [path], [scan] starts it.
  DartProjectScanner(
    this.fs,
    String path, {
    this.onProgress,
    this.progressInterval,
  }) : path = dartProjectCanonicalPath(fs, path);

  /// True once [cancel] was called.
  bool get cancelled => _cancelled;

  /// Stop the scan, it ends at the next folder.
  void cancel() => _cancelled = true;

  /// Scan the folder tree.
  ///
  /// Never throws, what could not be read is reported in
  /// [DartProjectScanResult.errors].
  Future<DartProjectScanResult> scan() async {
    // In milliseconds, as saved in the cache.
    var refreshed = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch,
    );
    var pathContext = fs.path;
    var projects = <String, DartProjectInfo>{};
    var gitFolders = <DartProjectGitFolderInfo>[];
    var errors = <String>[];

    DartProjectScanResult found({bool sorted = false}) {
      var list = projects.values.toList();
      var gitList = List.of(gitFolders);
      if (sorted) {
        list.sort(
          (project1, project2) => project1.path.compareTo(project2.path),
        );
        gitList.sort((git1, git2) => git1.path.compareTo(git2.path));
      }
      return DartProjectScanResult(
        path: path,
        projects: list,
        gitFolders: gitList,
        errors: List.of(errors),
        refreshed: refreshed,
        cancelled: _cancelled,
      );
    }

    /// Flag the workspace root holding the flutter package at [packagePath].
    void flagFlutterWorkspace(String packagePath) {
      var folder = packagePath;
      while (folder != path) {
        var parent = pathContext.dirname(folder);
        if (parent == folder) {
          return;
        }
        folder = parent;
        var project = projects[folder];
        if (project != null && project.kind.isWorkspace) {
          projects[folder] = project.copyWith(
            kind: DartProjectKind.flutterWorkspace,
          );
          return;
        }
      }
    }

    // Depth first, in name order: a workspace root is found before its
    // packages.
    var pending = <String>[path];
    while (pending.isNotEmpty && !_cancelled) {
      var folder = pending.removeLast();
      List<FileSystemEntity> entities;
      try {
        entities = await fs.directory(folder).list(followLinks: false).toList();
      } catch (e) {
        errors.add('$folder: $e');
        continue;
      }
      bool has(String name, {bool file = true}) => entities.any(
        (entity) =>
            (!file || entity is File) &&
            pathContext.basename(entity.path) == name,
      );
      var hasPubspec = has(_pubspecYaml);
      if (has(_dotGit, file: false)) {
        gitFolders.add(
          DartProjectGitFolderInfo(
            path: folder,
            remote: await _readGitRemote(folder),
            refreshed: refreshed,
          ),
        );
      }
      if (has(_localWorkspaceJson)) {
        // A local workspace wins over a dart project.
        projects[folder] = DartProjectInfo(
          path: folder,
          name: pathContext.basename(folder),
          kind: DartProjectKind.localWorkspace,
          refreshed: refreshed,
        );
        _progress(found);
      } else if (hasPubspec) {
        var project = await _readProject(folder, refreshed: refreshed);
        if (project != null) {
          projects[folder] = project.info;
          if (project.inWorkspace && project.info.kind.isFlutter) {
            flagFlutterWorkspace(folder);
          }
          _progress(found);
        }
      }
      var subFolders = <String>[];
      for (var entity in entities) {
        if (entity is! Directory) {
          continue;
        }
        var name = pathContext.basename(entity.path);
        if (name.startsWith('.') ||
            _ignoredFolderNames.contains(name) ||
            (hasPubspec && _ignoredProjectFolderNames.contains(name))) {
          continue;
        }
        subFolders.add(dartProjectCanonicalPath(fs, entity.path));
      }
      // Reversed, the first one is popped first.
      subFolders.sort((folder1, folder2) => folder2.compareTo(folder1));
      pending.addAll(subFolders);
    }
    return found(sorted: true);
  }

  /// The remote url of the git repository [folder], null when none.
  ///
  /// A `.git` file (a worktree, a sub module) points to the git folder,
  /// which points to the main one (`commondir`) for a worktree.
  Future<String?> _readGitRemote(String folder) async {
    var pathContext = fs.path;
    Future<String?> read(String path) async {
      try {
        return await fs.file(path).readAsString();
      } catch (_) {
        return null;
      }
    }

    var dotGit = pathContext.join(folder, _dotGit);
    var config = await read(pathContext.join(dotGit, 'config'));
    if (config == null) {
      var gitdir = RegExp(
        r'^gitdir:\s*(.+)$',
        multiLine: true,
      ).firstMatch(await read(dotGit) ?? '')?.group(1)?.trim();
      if (gitdir == null) {
        return null;
      }
      gitdir = pathContext.normalize(pathContext.join(folder, gitdir));
      var commondir = (await read(
        pathContext.join(gitdir, 'commondir'),
      ))?.trim();
      if (commondir != null && commondir.isNotEmpty) {
        gitdir = pathContext.normalize(pathContext.join(gitdir, commondir));
      }
      config = await read(pathContext.join(gitdir, 'config'));
    }
    return config == null ? null : gitConfigRemoteUrl(config);
  }

  /// Report what was [found] so far, unless it was reported less than
  /// [progressInterval] ago.
  void _progress(DartProjectScanResult Function() found) {
    var onProgress = this.onProgress;
    if (onProgress == null) {
      return;
    }
    var interval = progressInterval;
    if (interval != null) {
      var sinceProgress = _sinceProgress;
      if (sinceProgress != null && sinceProgress.elapsed < interval) {
        return;
      }
      _sinceProgress = Stopwatch()..start();
    }
    onProgress(found());
  }

  /// The project of [folder], null when its `pubspec.yaml` cannot be read or
  /// does not support the current dart sdk.
  Future<_ScannedProject?> _readProject(
    String folder, {
    required DateTime refreshed,
  }) async {
    try {
      var content = await fs
          .file(fs.path.join(folder, _pubspecYaml))
          .readAsString();
      var pubspecYaml = loadYaml(content);
      if (pubspecYaml is! Map) {
        return null;
      }
      var boundaries = pubspecYamlGetSdkBoundaries(pubspecYaml);
      if (boundaries == null || !boundaries.matches(dartVersion)) {
        return null;
      }
      var name = pubspecYamlGetPackageName(pubspecYaml);
      return _ScannedProject(
        DartProjectInfo(
          path: folder,
          name: (name == null || name.isEmpty)
              ? fs.path.basename(folder)
              : name,
          kind: dartProjectKindOf(
            isFlutter: pubspecYamlSupportsFlutter(pubspecYaml),
            isWorkspace: pubspecYamlIsWorkspaceRoot(pubspecYaml),
          ),
          refreshed: refreshed,
        ),
        inWorkspace: pubspecYamlHasWorkspaceResolution(pubspecYaml),
      );
    } catch (_) {
      return null;
    }
  }
}

/// A project found, and whether it is a package of a pub workspace.
class _ScannedProject {
  final DartProjectInfo info;
  final bool inWorkspace;

  _ScannedProject(this.info, {required this.inWorkspace});
}
