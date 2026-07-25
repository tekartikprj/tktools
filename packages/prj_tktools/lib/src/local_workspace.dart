import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:cv/cv_json.dart';
import 'package:path/path.dart';
import 'package:process_run/stdio.dart';

import 'tkpub.dart';
import 'tkpub_db.dart';
import 'utils.dart';

/// Config file name for a local workspace.
const localWorkspaceConfigFileName = 'local_workspace.json';

/// Model for local_workspace.json
///
/// - [links]: list of relative paths; each creates ./projects/basename -> absolute target
/// - [addGit]: list of package names to symlink at repo level via tkpub
/// - [add]: list of package names to symlink at package path level via tkpub
class DtkLocalWorkspace extends CvModelBase {
  /// Relative paths; each creates ./projects/basename -> absolute target.
  final links = CvListField<String>('links');

  /// Package names to symlink at repo level via tkpub.
  final addGit = CvListField<String>('add-git');

  /// Package names to symlink at package path level via tkpub.
  final add = CvListField<String>('add');

  @override
  CvFields get fields => [links, addGit, add];
}

/// A single resolved entry in a [DtkResolvedLocalWorkspace].
class DtkResolvedLocalWorkspaceResolved extends CvModelBase {
  /// Type of the entry (`links`, `add-git` or `add`).
  final type = CvField<String>('type');

  /// Original source (relative path or package name).
  final source = CvField<String>('source');

  /// Resolved path relative to the workspace.
  final path = CvField<String>('path');

  @override
  CvFields get fields => [type, source, path];
}

/// Version of the resolved local workspace format.
const dtkResolvedLocalWorkspaceVersion = 1;

/// Resolved local workspace, cached in .local/local_workspace/resolved.json.
class DtkResolvedLocalWorkspace extends CvModelBase {
  /// Input config that produced this resolution.
  final input = CvModelField<DtkLocalWorkspace>('input');

  /// Resolved entries.
  final resolved = CvModelListField<DtkResolvedLocalWorkspaceResolved>(
    'resolved',
  );

  /// Format version, see [dtkResolvedLocalWorkspaceVersion].
  final version = CvField<int>('version');

  @override
  CvFields get fields => [input, resolved, version];
}

/// Register the cv constructors for the local workspace models.
void initCvLocalWorkspace() {
  cvAddConstructors([
    DtkLocalWorkspace.new,
    DtkResolvedLocalWorkspace.new,
    DtkResolvedLocalWorkspaceResolved.new,
  ]);
}

/// e.g. https://github.com/tekartik/common.dart -> true
/// e.g. git@github.com:tekartik/common.dart.git -> true
bool _isGitUrl(String text) {
  return text.startsWith('https://') || text.startsWith('git@');
}

/// 2 parts or more
/// e.g. tekartik/common.dart -> true
/// e.g. user/repo/subpath1/subpath2 -> true
bool _isGitShortPath(String text) {
  var parts = text.split('/');
  return parts.length >= 2 && parts.every((part) => part.isNotEmpty);
}

/// Get the github-relative path (org/repo or org/repo/subpath) from a git URL or short path.
/// e.g. https://github.com/tekartik/common.dart -> tekartik/common.dart
/// e.g. git@github.com:tekartik/common.dart.git -> tekartik/common.dart
/// e.g. user/repo/subpath1/subpath2 -> user/repo/subpath1/subpath2
String _githubRelPath(String gitUrl) {
  String path;
  if (gitUrl.startsWith('git@')) {
    path = gitUrl.split(':').last;
  } else if (_isGitUrl(gitUrl)) {
    path = Uri.parse(gitUrl).path;
    if (path.startsWith('/')) path = path.substring(1);
  } else {
    path = gitUrl;
  }
  if (path.endsWith('.git')) path = path.substring(0, path.length - 4);
  return path;
}

/// Create (replacing any existing) a symlink at [absoluteLinkPath] pointing to
/// [localTarget].
void localWorkspaceCreateSymlink(String absoluteLinkPath, String localTarget) {
  var link = Link(absoluteLinkPath);
  try {
    link.deleteSync(recursive: true);
  } catch (_) {}
  Link(absoluteLinkPath).createSync(localTarget, recursive: true);
}

/// Symlink the specific package path within its git repo (via tkpub).
Future<void> localWorkspaceDoAdd(
  String packageName,
  String path,
  String githubTop,
) async {
  TkPubDbPackage dbPackage;
  try {
    dbPackage = await tkPubDbAction((db) => db.getPackage(packageName));
  } catch (_) {
    stderr.writeln('Package $packageName not found in tkpub config');
    return;
  }

  var gitUrl = dbPackage.gitUrl.v!;
  var gitPath = dbPackage.gitPath.v;
  var repoRelPath = _githubRelPath(gitUrl);
  var linkRelPath = gitPath != null && gitPath.isNotEmpty
      ? join(repoRelPath, gitPath)
      : repoRelPath;

  var repoLinkPath = normalize(absolute(join(path, 'projects', repoRelPath)));
  if (Link(repoLinkPath).existsSync()) {
    throw StateError(
      '$packageName: repo link already exists at projects/$repoRelPath '
      '(created by add-git). Remove it first or use add-git.',
    );
  }

  var localTarget = await tkPubGetPackageLocalPath(githubTop, packageName);
  var absoluteLinkPath = normalize(
    absolute(join(path, 'projects', linkRelPath)),
  );
  stdout.writeln('$packageName -> projects/$linkRelPath');
  localWorkspaceCreateSymlink(absoluteLinkPath, localTarget);
}

/// Symlink the whole git repo for a package to a local subfolder (via tkpub).
Future<void> localWorkspaceDoAddGit(
  String packageName,
  String path,
  String githubTop,
) async {
  String gitUrl;
  if (_isGitShortPath(packageName) || _isGitUrl(packageName)) {
    gitUrl = _githubRelPath(packageName);
  } else {
    TkPubDbPackage dbPackage;
    try {
      dbPackage = await tkPubDbAction((db) => db.getPackage(packageName));
    } catch (_) {
      stderr.writeln('Package $packageName not found in tkpub config');
      return;
    }

    gitUrl = dbPackage.gitUrl.v!;
  }
  var repoRelPath = _githubRelPath(gitUrl);
  var localTarget = normalize(absolute(join(githubTop, repoRelPath)));
  var absoluteLinkPath = normalize(
    absolute(join(path, 'projects', repoRelPath)),
  );
  stdout.writeln('$packageName -> projects/$repoRelPath');
  localWorkspaceCreateSymlink(absoluteLinkPath, localTarget);
}

/// Helper to load a `local_workspace.json` config and resolve its folders.
///
/// This is the reusable core shared by the `local_workspace` CLI tool and by
/// tools that need the list of workspace folders (aggregated projects).
class LocalWorkspaceHelper {
  /// Workspace root path (where `local_workspace.json` lives).
  final String path;

  /// Create a helper for the workspace at [path].
  LocalWorkspaceHelper({required this.path}) {
    initCvLocalWorkspace();
  }

  /// The `local_workspace.json` config file.
  File get configFile => File(join(path, localWorkspaceConfigFileName));

  /// The cached resolved workspace file.
  File get resolvedFile =>
      File(join(path, '.local', 'local_workspace', 'resolved.json'));

  /// The cached resolved input file.
  File get resolvedInputFile =>
      File(join(path, '.local', 'local_workspace', 'resolved_input.json'));

  DtkResolvedLocalWorkspace? _cachedResolvedLocalWorkspace;
  DtkLocalWorkspace? _cachedConfig;
  String? _cachedConfigContent;
  List<String>? _cachedResolvedFolders;

  Future<DtkLocalWorkspace> loadConfig() async {
    var file = configFile;
    if (!file.existsSync()) {
      throw StateError('$localWorkspaceConfigFileName not found in $path');
    }
    var content = file.readAsStringSync();
    if (_cachedConfig != null && _cachedConfigContent == content) {
      return _cachedConfig!;
    }
    var config = content.cv<DtkLocalWorkspace>();
    _cachedConfig = config;
    _cachedConfigContent = content;
    _cachedResolvedFolders = null;
    return config;
  }

  /// Check whether an input config changed from the one stored in resolved_input.json or resolved.json.
  Future<bool> checkConfig() async {
    if (!resolvedFile.existsSync() || !resolvedInputFile.existsSync()) {
      return false;
    }

    if (!configFile.existsSync()) {
      return false;
    }

    Map<String, dynamic> inputMap;
    try {
      inputMap = (jsonDecode(configFile.readAsStringSync()) as Map)
          .cast<String, dynamic>();
    } catch (_) {
      return false;
    }

    Map<String, dynamic> storedInputMap;
    try {
      var storedInputJsonString = resolvedInputFile.readAsStringSync();
      var storedInputJson = (jsonDecode(storedInputJsonString) as Map)
          .cast<String, dynamic>();
      if (storedInputJson['version'] != dtkResolvedLocalWorkspaceVersion) {
        return false;
      }
      storedInputMap = (storedInputJson['input'] as Map)
          .cast<String, dynamic>();
    } catch (_) {
      try {
        var storedResolvedJsonString = resolvedFile.readAsStringSync();
        var storedResolved = jsonDecode(storedResolvedJsonString) as Map;
        if (storedResolved['version'] != dtkResolvedLocalWorkspaceVersion) {
          return false;
        }
        storedInputMap = (storedResolved['input'] as Map)
            .cast<String, dynamic>();
      } catch (_) {
        return false;
      }
    }

    return const DeepCollectionEquality().equals(inputMap, storedInputMap);
  }

  Future<DtkResolvedLocalWorkspace?> _readResolvedConfig() async {
    var file = resolvedFile;
    if (!file.existsSync()) {
      return null;
    }
    try {
      var content = file.readAsStringSync();
      return content.cv<DtkResolvedLocalWorkspace>();
    } catch (_) {
      return null;
    }
  }

  Future<DtkResolvedLocalWorkspace?> getResolvedConfig({
    bool force = false,
  }) async {
    // Check if it is up to date
    if (!await checkConfig()) {
      _cachedResolvedLocalWorkspace = null;
      return null;
    }

    if (!force && _cachedResolvedLocalWorkspace != null) {
      return _cachedResolvedLocalWorkspace;
    }

    var resolved = await _readResolvedConfig();
    if (resolved != null) {
      _cachedResolvedLocalWorkspace = resolved;
    }
    return resolved;
  }

  /// Get the resolved config if up to date, or resolve it and write to file.
  Future<DtkResolvedLocalWorkspace> getOrResolve({bool force = false}) async {
    if (!force) {
      var resolved = await getResolvedConfig();
      if (resolved != null) {
        return resolved;
      }
    }

    var config = await loadConfig();
    var resolved = await resolve(config);
    await writeResolved(resolved);
    return resolved;
  }

  Future<DtkResolvedLocalWorkspace> resolve(DtkLocalWorkspace config) async {
    final resolvedList = <DtkResolvedLocalWorkspaceResolved>[];

    for (var relTarget in config.links.v ?? <String>[]) {
      var absoluteTarget = normalize(absolute(join(path, relTarget)));
      if (!Directory(absoluteTarget).existsSync()) {
        stderr.writeln('Warning: link target $absoluteTarget does not exist');
        throw StateError('Link target $absoluteTarget does not exist');
      }
      var resolved = relative(absoluteTarget, from: absolute(path));
      resolvedList.add(
        DtkResolvedLocalWorkspaceResolved()
          ..type.v = 'links'
          ..source.v = relTarget
          ..path.v = resolved,
      );
    }

    final addGitList = config.addGit.v ?? [];
    final addList = config.add.v ?? [];
    if (addGitList.isNotEmpty || addList.isNotEmpty) {
      var githubTop = normalize(
        absolute(await tkPubFindGithubTop(dirPath: path)),
      );
      for (var packageName in addGitList) {
        String gitUrl;
        if (_isGitShortPath(packageName) || _isGitUrl(packageName)) {
          gitUrl = _githubRelPath(packageName);
        } else {
          try {
            var dbPackage = await tkPubDbAction(
              (db) => db.getPackage(packageName),
            );
            gitUrl = dbPackage.gitUrl.v!;
          } catch (_) {
            stderr.writeln('Package $packageName not found in tkpub config');
            throw StateError('Package $packageName not found in tkpub config');
          }
        }
        var repoRelPath = _githubRelPath(gitUrl);
        var localTarget = normalize(absolute(join(githubTop, repoRelPath)));
        if (!Directory(localTarget).existsSync()) {
          stderr.writeln('Warning: git target $localTarget does not exist');
          throw StateError('Git target $localTarget does not exist');
        }
        var resolved = relative(localTarget, from: absolute(path));
        resolvedList.add(
          DtkResolvedLocalWorkspaceResolved()
            ..type.v = 'add-git'
            ..source.v = packageName
            ..path.v = resolved,
        );
      }
      for (var packageName in addList) {
        try {
          await tkPubDbAction((db) => db.getPackage(packageName));
          var localTarget = await tkPubGetPackageLocalPath(
            githubTop,
            packageName,
          );
          var resolved = relative(localTarget, from: absolute(path));
          resolvedList.add(
            DtkResolvedLocalWorkspaceResolved()
              ..type.v = 'add'
              ..source.v = packageName
              ..path.v = resolved,
          );
        } catch (_) {
          stderr.writeln('Package $packageName not found in tkpub config');
          throw StateError('Package $packageName not found in tkpub config');
        }
      }
    }

    var result = DtkResolvedLocalWorkspace()
      ..input.v = config
      ..resolved.v = resolvedList.isNotEmpty ? resolvedList : null
      ..version.v = dtkResolvedLocalWorkspaceVersion;

    return result;
  }

  Future<void> writeResolved(DtkResolvedLocalWorkspace resolved) async {
    var localDir = Directory(join(path, '.local', 'local_workspace'));
    localDir.createSync(recursive: true);

    var encoder = const JsonEncoder.withIndent('  ');
    resolvedFile.writeAsStringSync('${encoder.convert(resolved.toMap())}\n');
    stdout.writeln('Created ${resolvedFile.path}');

    var inputMap = {
      'version': dtkResolvedLocalWorkspaceVersion,
      'input': resolved.input.v?.toMap() ?? {},
    };
    resolvedInputFile.writeAsStringSync('${encoder.convert(inputMap)}\n');
    stdout.writeln('Created ${resolvedInputFile.path}');

    _cachedResolvedLocalWorkspace = resolved;
    _cachedResolvedFolders = null;
  }

  /// Absolute canonical top folders of the workspace (including the root `.`).
  Future<List<String>> getTopFolders() async {
    await getOrResolve();
    var folders = <String>{};

    void addFolder(String path) {
      if (isRelative(path)) {
        path = join(this.path, path);
      }
      folders.add(canonicalize(path));
    }

    addFolder('.');

    var resolvedConfig = await getResolvedConfig();
    if (resolvedConfig != null) {
      var resolved = resolvedConfig.resolved.v;
      if (resolved != null) {
        for (var entry in resolved) {
          var p = entry.path.v;
          if (p != null) {
            addFolder(p);
          }
        }
      }
    }
    return folders.toList();
  }

  /// Relative (to [path]) folders of the workspace (including the root `.`).
  Future<List<String>> resolveFolders(DtkLocalWorkspace config) async {
    await getOrResolve();
    if (identical(config, _cachedConfig) && _cachedResolvedFolders != null) {
      return _cachedResolvedFolders!;
    }

    var folders = <String>['.'];

    var resolvedConfig = await getResolvedConfig();
    if (resolvedConfig != null) {
      var resolved = resolvedConfig.resolved.v;
      if (resolved != null) {
        for (var entry in resolved) {
          var p = entry.path.v;
          if (p != null) {
            folders.add(p);
          }
        }
      }
    } else {
      for (var relTarget in config.links.v ?? <String>[]) {
        var absoluteTarget = normalize(absolute(join(path, relTarget)));
        folders.add(relative(absoluteTarget, from: absolute(path)));
      }

      final addGitList = config.addGit.v ?? [];
      final addList = config.add.v ?? [];
      if (addGitList.isNotEmpty || addList.isNotEmpty) {
        var githubTop = normalize(
          absolute(await tkPubFindGithubTop(dirPath: path)),
        );
        for (var packageName in addGitList) {
          String gitUrl;
          if (_isGitShortPath(packageName) || _isGitUrl(packageName)) {
            gitUrl = _githubRelPath(packageName);
          } else {
            try {
              var dbPackage = await tkPubDbAction(
                (db) => db.getPackage(packageName),
              );
              gitUrl = dbPackage.gitUrl.v!;
            } catch (_) {
              stderr.writeln('Package $packageName not found in tkpub config');
              continue;
            }
          }
          var repoRelPath = _githubRelPath(gitUrl);
          var localTarget = normalize(absolute(join(githubTop, repoRelPath)));
          folders.add(relative(localTarget, from: absolute(path)));
        }
        for (var packageName in addList) {
          try {
            await tkPubDbAction((db) => db.getPackage(packageName));
            var localTarget = await tkPubGetPackageLocalPath(
              githubTop,
              packageName,
            );
            folders.add(relative(localTarget, from: absolute(path)));
          } catch (_) {
            stderr.writeln('Package $packageName not found in tkpub config');
            continue;
          }
        }
      }
    }

    // Keep unique paths, keeping order
    var uniqueFolders = <String>[];
    var seen = <String>{};
    for (var folder in folders) {
      if (seen.add(folder)) {
        uniqueFolders.add(folder);
      }
    }

    _cachedConfig = config;
    _cachedResolvedFolders = uniqueFolders;

    return uniqueFolders;
  }

  Future<void> setupVsCode(DtkLocalWorkspace config) async {
    var uniqueFolders = await resolveFolders(config);

    var vsCodeFolders = <String>[];
    var seen = <String>{};
    for (var folder in uniqueFolders) {
      // Normalize path separator to forward slashes for cross-platform VS Code compatibility
      var normalizedFolder = posix.joinAll(split(folder));
      if (seen.add(normalizedFolder)) {
        vsCodeFolders.add(normalizedFolder);
      }
    }

    var dirName = basename(normalize(absolute(path)));
    var workspaceFile = File(join(path, '$dirName.code-workspace'));

    var content = {
      'folders': [
        for (var folder in vsCodeFolders) {'path': folder},
      ],
      'settings': <String, dynamic>{},
    };

    var encoder = const JsonEncoder.withIndent('  ');
    workspaceFile.writeAsStringSync('${encoder.convert(content)}\n');
    stdout.writeln('Created ${workspaceFile.path}');
  }

  Future<void> setupIdea(DtkLocalWorkspace config) async {
    var uniqueFolders = await resolveFolders(config);

    var absolutePath = normalize(absolute(path));
    var absoluteFolders = uniqueFolders
        .map((folder) => normalize(absolute(join(path, folder))))
        .toList();

    String? parentFolder;
    for (var folder in absoluteFolders) {
      if (isWithin(folder, absolutePath)) {
        parentFolder = folder;
        break;
      }
    }
    var ideaProjectDir = parentFolder ?? absolutePath;
    var dirName = basename(ideaProjectDir);
    var ideaDir = Directory(join(ideaProjectDir, '.idea'));
    if (!ideaDir.existsSync()) {
      ideaDir.createSync(recursive: true);
    }

    // Write modules.xml
    var modulesFile = File(join(ideaDir.path, 'modules.xml'));
    var modulesContent =
        '''
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectModuleManager">
    <modules>
      <module fileurl="file://\$PROJECT_DIR\$/.idea/$dirName.iml" filepath="\$PROJECT_DIR\$/.idea/$dirName.iml" />
    </modules>
  </component>
</project>
''';
    modulesFile.writeAsStringSync(modulesContent);

    // Filter absoluteFolders to only keep content roots (which are not subfolders of other content roots)
    var contentRoots = <String>[];
    for (var folder in absoluteFolders) {
      var isNested = false;
      for (var other in absoluteFolders) {
        if (folder != other && isWithin(other, folder)) {
          isNested = true;
          break;
        }
      }
      if (!isNested) {
        contentRoots.add(folder);
      }
    }

    // Write $dirName.iml
    var imlFile = File(join(ideaDir.path, '$dirName.iml'));
    var contentEntries = StringBuffer();
    for (var contentRoot in contentRoots) {
      var relativeToProject = relative(contentRoot, from: ideaProjectDir);
      var normalizedRelative = posix.joinAll(split(relativeToProject));
      var contentUrl = (normalizedRelative == '.' || normalizedRelative.isEmpty)
          ? 'file://\$MODULE_DIR\$'
          : 'file://\$MODULE_DIR\$/$normalizedRelative';
      contentEntries.writeln('    <content url="$contentUrl">');

      // Add exclusions for all unique folders that are descendant of or equal to this contentRoot
      for (var f in absoluteFolders) {
        if (f == contentRoot || isWithin(contentRoot, f)) {
          var relF = relative(f, from: ideaProjectDir);
          var normF = posix.joinAll(split(relF));
          var excludeUrl = (normF == '.' || normF.isEmpty)
              ? 'file://\$MODULE_DIR\$'
              : 'file://\$MODULE_DIR\$/$normF';
          contentEntries.writeln(
            '      <excludeFolder url="$excludeUrl/.dart_tool" />',
          );
          contentEntries.writeln(
            '      <excludeFolder url="$excludeUrl/.pub" />',
          );
          contentEntries.writeln(
            '      <excludeFolder url="$excludeUrl/build" />',
          );
        }
      }
      contentEntries.writeln('    </content>');
    }

    var imlContent =
        '''
<?xml version="1.0" encoding="UTF-8"?>
<module type="JAVA_MODULE" version="4">
  <component name="NewModuleRootManager" inherit-compiler-output="true">
    <exclude-output />
${contentEntries.toString().trimRight()}
    <orderEntry type="inheritedJdk" />
    <orderEntry type="sourceFolder" forTests="false" />
    <orderEntry type="library" name="Dart SDK" level="project" />
    <orderEntry type="library" name="Dart Packages" level="project" />
  </component>
</module>
''';
    imlFile.writeAsStringSync(imlContent);
    stdout.writeln('Created ${imlFile.path}');
    stdout.writeln('Created ${modulesFile.path}');
  }

  Future<void> setupClaude(DtkLocalWorkspace config) async {
    var uniqueFolders = await resolveFolders(config);

    // Keep unique absolute paths
    var uniqueAbsolutePaths = <String>[];
    var seen = <String>{};
    for (var folder in uniqueFolders) {
      var absoluteFolder = normalize(absolute(join(path, folder)));
      var normalizedFolder = posix.joinAll(split(absoluteFolder));
      if (seen.add(normalizedFolder)) {
        uniqueAbsolutePaths.add(normalizedFolder);
      }
    }

    var claudeDir = Directory(join(path, '.claude'));
    if (!claudeDir.existsSync()) {
      claudeDir.createSync(recursive: true);
    }

    var settingsFile = File(join(claudeDir.path, 'settings.json'));
    var settings = <String, dynamic>{};
    if (settingsFile.existsSync()) {
      try {
        settings = (jsonDecode(settingsFile.readAsStringSync()) as Map)
            .cast<String, dynamic>();
      } catch (_) {}
    }

    // Get or create permissions map
    var permissions = settings['permissions'];
    if (permissions is! Map) {
      permissions = <String, dynamic>{};
      settings['permissions'] = permissions;
    } else {
      permissions = permissions.cast<String, dynamic>();
    }

    // Get or create additionalDirectories list
    var additionalDirectories = permissions['additionalDirectories'];
    if (additionalDirectories is! List) {
      additionalDirectories = <dynamic>[];
      permissions['additionalDirectories'] = additionalDirectories;
    } else {
      additionalDirectories = List<dynamic>.from(additionalDirectories);
      permissions['additionalDirectories'] = additionalDirectories;
    }

    // Add unique folders if not already present
    var modified = false;
    for (var absoluteFolder in uniqueAbsolutePaths) {
      if (!additionalDirectories.contains(absoluteFolder)) {
        additionalDirectories.add(absoluteFolder);
        modified = true;
      }
    }

    if (modified) {
      var encoder = const JsonEncoder.withIndent('  ');
      settingsFile.writeAsStringSync('${encoder.convert(settings)}\n');
      stdout.writeln('Updated ${settingsFile.path}');
    } else {
      stdout.writeln('No changes needed for ${settingsFile.path}');
    }
  }

  Future<void> setupAgy(DtkLocalWorkspace config) async {
    var uniqueFolders = await resolveFolders(config);

    // Keep unique absolute paths
    var uniqueAbsolutePaths = <String>[];
    var seen = <String>{};
    for (var folder in uniqueFolders) {
      var absoluteFolder = normalize(absolute(join(path, folder)));
      var normalizedFolder = posix.joinAll(split(absoluteFolder));
      if (seen.add(normalizedFolder)) {
        uniqueAbsolutePaths.add(normalizedFolder);
      }
    }

    var agyDir = Directory(join(path, '.gemini', 'antigravity-cli'));
    if (!agyDir.existsSync()) {
      agyDir.createSync(recursive: true);
    }

    var settingsFile = File(join(agyDir.path, 'settings.json'));
    var settings = <String, dynamic>{};
    if (settingsFile.existsSync()) {
      try {
        settings = (jsonDecode(settingsFile.readAsStringSync()) as Map)
            .cast<String, dynamic>();
      } catch (_) {}
    }

    // Get or create permissions map
    var permissions = settings['permissions'];
    if (permissions is! Map) {
      permissions = <String, dynamic>{};
      settings['permissions'] = permissions;
    } else {
      permissions = permissions.cast<String, dynamic>();
    }

    // Get or create allow list
    var allow = permissions['allow'];
    if (allow is! List) {
      allow = <dynamic>[];
      permissions['allow'] = allow;
    } else {
      allow = List<dynamic>.from(allow);
      permissions['allow'] = allow;
    }

    // Add unique folders if not already present
    var modified = false;
    for (var absoluteFolder in uniqueAbsolutePaths) {
      var readPermission = 'read_file($absoluteFolder)';
      var writePermission = 'write_file($absoluteFolder)';

      if (!allow.contains(readPermission)) {
        allow.add(readPermission);
        modified = true;
      }
      if (!allow.contains(writePermission)) {
        allow.add(writePermission);
        modified = true;
      }
    }

    if (modified) {
      var encoder = const JsonEncoder.withIndent('  ');
      settingsFile.writeAsStringSync('${encoder.convert(settings)}\n');
      stdout.writeln('Updated ${settingsFile.path}');
    } else {
      stdout.writeln('No changes needed for ${settingsFile.path}');
    }
  }
}
