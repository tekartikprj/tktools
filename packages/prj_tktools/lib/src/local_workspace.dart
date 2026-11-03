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
/// - [addDir]: list of relative or absolute folder paths, added as is (no symlink)
class DtkLocalWorkspace extends CvModelBase {
  /// Relative paths; each creates ./projects/basename -> absolute target.
  final links = CvListField<String>('links');

  /// Package names to symlink at repo level via tkpub.
  final addGit = CvListField<String>('add-git');

  /// Package names to symlink at package path level via tkpub.
  final add = CvListField<String>('add');

  /// Existing folders (relative to the workspace or absolute) added to the
  /// workspace as is, no symlink is created and no tkpub lookup is needed.
  final addDir = CvListField<String>('add-dir');

  @override
  CvFields get fields => [links, addGit, add, addDir];
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

/// Write [content] to [file] only if it differs from the existing content.
///
/// Reports what happened on stdout (`Created`, `Updated` or `No changes
/// needed for`), returns true when the file was created or updated.
bool localWorkspaceWriteFileIfChanged(File file, String content) {
  if (file.existsSync()) {
    String? existing;
    try {
      existing = file.readAsStringSync();
    } catch (_) {}
    if (existing == content) {
      stdout.writeln('No changes needed for ${file.path}');
      return false;
    }
    file.writeAsStringSync(content);
    stdout.writeln('Updated ${file.path}');
    return true;
  }
  file.writeAsStringSync(content);
  stdout.writeln('Created ${file.path}');
  return true;
}

/// Why IntelliJ may have the project of the `.idea` folder [ideaDirPath]
/// open, null when nothing shows it.
///
/// IntelliJ reads `.idea/modules.xml` and the module files only when it
/// opens a project and writes its own module over them when it closes it:
/// files written while the project is open are ignored, then lost.
///
/// The signs: a `workspace.xml` without `modules.xml` (IntelliJ opened the
/// folder before any setup) or a JetBrains terminal (`TERMINAL_EMULATOR` in
/// [environment], [Platform.environment] by default).
String? localWorkspaceIdeaOpenReason(
  String ideaDirPath, {
  Map<String, String>? environment,
}) {
  if (File(join(ideaDirPath, 'workspace.xml')).existsSync() &&
      !File(join(ideaDirPath, 'modules.xml')).existsSync()) {
    return '.idea/workspace.xml exists without .idea/modules.xml';
  }
  environment ??= Platform.environment;
  var terminal = environment['TERMINAL_EMULATOR'];
  if (terminal != null && terminal.startsWith('JetBrains')) {
    return 'running in a JetBrains terminal';
  }
  return null;
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

  /// Load (and cache) the `local_workspace.json` config.
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
      // Compare through the model so that unknown fields are ignored on both
      // sides (the stored input is a model map too).
      inputMap = configFile
          .readAsStringSync()
          .cv<DtkLocalWorkspace>()
          .toMap()
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

  /// Get the cached resolved config, if [checkConfig] reports it is up to date.
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

  /// Resolve [config] into absolute/relative folders, without reading or
  /// writing any cache file.
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

    for (var dirTarget in config.addDir.v ?? <String>[]) {
      // join() handles both relative (to the workspace) and absolute paths.
      var absoluteTarget = normalize(absolute(join(path, dirTarget)));
      if (!Directory(absoluteTarget).existsSync()) {
        stderr.writeln('Warning: dir target $absoluteTarget does not exist');
        continue;
      }
      var resolved = relative(absoluteTarget, from: absolute(path));
      resolvedList.add(
        DtkResolvedLocalWorkspaceResolved()
          ..type.v = 'add-dir'
          ..source.v = dirTarget
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
          // throw StateError('Git target $localTarget does not exist locally');
          continue;
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

  /// Write [resolved] to [resolvedFile] and [resolvedInputFile], updating the cache.
  Future<void> writeResolved(DtkResolvedLocalWorkspace resolved) async {
    var localDir = Directory(join(path, '.local', 'local_workspace'));
    localDir.createSync(recursive: true);

    var encoder = const JsonEncoder.withIndent('  ');
    localWorkspaceWriteFileIfChanged(
      resolvedFile,
      '${encoder.convert(resolved.toMap())}\n',
    );

    var inputMap = {
      'version': dtkResolvedLocalWorkspaceVersion,
      'input': resolved.input.v?.toMap() ?? {},
    };
    localWorkspaceWriteFileIfChanged(
      resolvedInputFile,
      '${encoder.convert(inputMap)}\n',
    );

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
  ///
  /// The folders come from the resolved config of the config file
  /// ([getOrResolve]); [config] is the loaded config, used as the cache key.
  Future<List<String>> resolveFolders(DtkLocalWorkspace config) async {
    var resolvedConfig = await getOrResolve();
    if (identical(config, _cachedConfig) && _cachedResolvedFolders != null) {
      return _cachedResolvedFolders!;
    }

    var folders = <String>['.'];
    for (var entry
        in resolvedConfig.resolved.v ?? <DtkResolvedLocalWorkspaceResolved>[]) {
      var p = entry.path.v;
      if (p != null) {
        folders.add(p);
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

  /// Write a `<dir_name>.code-workspace` file listing the resolved folders.
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
    localWorkspaceWriteFileIfChanged(
      workspaceFile,
      '${encoder.convert(content)}\n',
    );
  }

  /// Write IntelliJ project files (`.idea/modules.xml` and `.idea/<dir_name>.iml`)
  /// with content roots for the resolved folders.
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
    // Before writing, modules.xml is one of the signs.
    var ideaOpenReason = localWorkspaceIdeaOpenReason(ideaDir.path);
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
    var imlChanged = localWorkspaceWriteFileIfChanged(imlFile, imlContent);
    var modulesChanged = localWorkspaceWriteFileIfChanged(
      modulesFile,
      modulesContent,
    );
    if ((imlChanged || modulesChanged) && ideaOpenReason != null) {
      stderr.writeln('''
Warning: IntelliJ may have this project open ($ideaOpenReason).
IntelliJ reads .idea/modules.xml and .idea/$dirName.iml only when it opens
the project, and writes its own module over them when it closes it.
If folders are missing in IntelliJ: close the project, run
`lw setup-idea` again from a terminal outside IntelliJ, then reopen it.''');
    }
  }

  /// Update `.claude/settings.json` with the resolved folders added to
  /// `permissions.additionalDirectories`.
  Future<void> setupClaude(DtkLocalWorkspace config) async {
    var uniqueAbsolutePaths = await _uniqueAbsoluteFolders(config);

    var settingsFile = File(join(path, '.claude', 'settings.json'));
    _updateSettingsPermissionsList(
      settingsFile,
      'additionalDirectories',
      uniqueAbsolutePaths,
    );
  }

  /// Update `.gemini/antigravity-cli/settings.json` with read/write
  /// permissions for the resolved folders.
  Future<void> setupAgy(DtkLocalWorkspace config) async {
    var uniqueAbsolutePaths = await _uniqueAbsoluteFolders(config);

    var settingsFile = File(
      join(path, '.gemini', 'antigravity-cli', 'settings.json'),
    );
    _updateSettingsPermissionsList(settingsFile, 'allow', [
      for (var absoluteFolder in uniqueAbsolutePaths) ...[
        'read_file($absoluteFolder)',
        'write_file($absoluteFolder)',
      ],
    ]);
  }

  /// Unique absolute posix paths of the resolved folders.
  Future<List<String>> _uniqueAbsoluteFolders(DtkLocalWorkspace config) async {
    var uniqueFolders = await resolveFolders(config);
    var uniqueAbsolutePaths = <String>[];
    var seen = <String>{};
    for (var folder in uniqueFolders) {
      var absoluteFolder = normalize(absolute(join(path, folder)));
      var normalizedFolder = posix.joinAll(split(absoluteFolder));
      if (seen.add(normalizedFolder)) {
        uniqueAbsolutePaths.add(normalizedFolder);
      }
    }
    return uniqueAbsolutePaths;
  }
}

/// Add [entries] to the `permissions.<listKey>` list of the json
/// [settingsFile], keeping every other setting.
///
/// A settings file that cannot be read as a json object is left untouched and
/// a [StateError] is thrown (it used to be overwritten with only the
/// permissions).
void _updateSettingsPermissionsList(
  File settingsFile,
  String listKey,
  List<String> entries,
) {
  var settings = <String, dynamic>{};
  if (settingsFile.existsSync()) {
    var content = settingsFile.readAsStringSync();
    if (content.trim().isNotEmpty) {
      Object? decoded;
      try {
        decoded = jsonDecode(content);
      } catch (e) {
        throw StateError(
          'Cannot read ${settingsFile.path} ($e), fix it or remove it, it was not modified',
        );
      }
      if (decoded is! Map) {
        throw StateError(
          '${settingsFile.path} is not a json object, fix it or remove it, it was not modified',
        );
      }
      settings = decoded.cast<String, dynamic>();
    }
  }

  // Get or create permissions map
  var permissions = settings['permissions'];
  if (permissions is! Map) {
    permissions = <String, dynamic>{};
    settings['permissions'] = permissions;
  } else {
    permissions = permissions.cast<String, dynamic>();
  }

  // Get or create the list
  var list = permissions[listKey];
  if (list is! List) {
    list = <dynamic>[];
  } else {
    list = List<dynamic>.from(list);
  }
  permissions[listKey] = list;

  // Add unique entries if not already present
  var modified = false;
  for (var entry in entries) {
    if (!list.contains(entry)) {
      list.add(entry);
      modified = true;
    }
  }

  if (modified) {
    settingsFile.parent.createSync(recursive: true);
    var encoder = const JsonEncoder.withIndent('  ');
    settingsFile.writeAsStringSync('${encoder.convert(settings)}\n');
    stdout.writeln('Updated ${settingsFile.path}');
  } else {
    stdout.writeln('No changes needed for ${settingsFile.path}');
  }
}
