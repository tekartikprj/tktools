import 'dart:io';

import 'package:cv/cv.dart';
import 'package:dev_build/menu/menu_run_ci.dart';
import 'package:dev_build/shell.dart';
import 'package:fs_shim/utils/path.dart' show toPosixPath;
import 'package:path/path.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_mustache/mustache.dart';
import 'package:tekartik_prj_tktools/file_lines_io.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:tekartik_prj_tktools/yaml_edit.dart';

/// Dart SDK constraint to use if none is specified
var defaultDartSdkConstraint = '^3.9.0';

extension on String {
  /// Get lines
  List<String> get lines => LineSplitter.split(this).toList();
}

Future<String> _render(String template, Model values) async {
  return (await render(template, values))!;
}

Future<List<String>> _renderLines(List<String> templates, Model values) async {
  var list = <String>[];
  for (var template in templates) {
    list.addAll((await _render(template, values)).lines);
  }
  return list;
}

/// Get the pubspec.yaml lines for an empty workspace project
Future<List<String>> getWorkspacePubspecLines() async {
  return _workspacePubspec;
}

final _workspacePubspec =
    '''
name: _
publish_to: none
environment:
  sdk: $defaultDartSdkConstraint
workspace:
'''
        .lines;
final _projectPubspec =
    '''
name: {{projectName}}
publish_to: none
environment:
  sdk: $defaultDartSdkConstraint
resolution: workspace
'''
        .lines;

/// Get the pubspec.yaml lines for an empty project
Future<List<String>> getEmptyProjectPubspecLines({
  required String projectName,
}) async {
  return _renderLines(_projectPubspec, {'projectName': projectName});
}

/// Dtk project
class DtkProject {
  /// Dir path
  final String path;

  /// Create a project from a path.
  DtkProject(this.path);

  /// Create an empty dart project
  Future<void> createEmptyProject({required String projectName}) async {
    var file = File(join(path, 'pubspec.yaml'));
    if (!file.existsSync()) {
      await file.writeLines(
        await getEmptyProjectPubspecLines(projectName: projectName),
      );
      stdout.writeln('wrote $file');
    } else {
      stderr.writeln('$file already exists');
    }
  }

  /// Create a workspace root project
  Future<void> createWorkspaceRootProject() async {
    var file = File(join(path, 'pubspec.yaml'));
    if (!file.existsSync()) {
      await file.writeLines(await getWorkspacePubspecLines());
      stdout.writeln('wrote $file');
    } else {
      stderr.writeln('$file already exists');
    }
  }

  /// Add current project to workspace
  Future<void> addToWorkspace({bool? keepExistingWorkspaceResolution}) async {
    await _lock.synchronized(() async {
      await _addToWorkspace();
    });
  }

  /// Remove current project from workspace
  Future<void> removeFromWorkspace() async {
    await _lock.synchronized(() async {
      await _setWorkspaceResolution(false);
      var parent = await _findParentRootWorkspaceOrNull();
      if (parent == null) {
        return;
      }
      var relativePath = toPosixPath(relative(path, from: parent));
      var pubspecMap = await pathGetPubspecYamlMap(parent);
      var workspace = pubspecMap['workspace'];
      if (workspace is List) {
        if (!workspace.contains(relativePath)) {
          return;
        }
        var newList = List<String>.from(workspace)..remove(relativePath);
        var file = File(join(parent, 'pubspec.yaml'));
        var yamlEditor = YamlEditor(await file.readAsString());
        stdout.writeln('Setting $newList to workspace');
        yamlEditor.updateOrAdd(['workspace'], newList);
        await file.writeLinesIfNeeded(yamlEditor.toLines(), verbose: true);
      }
    });
  }

  /// Make static for cross project lock
  static final _lock = Lock();

  /// Add current project to workspace
  Future<void> _addToWorkspace() async {
    await _setWorkspaceResolution(true);
    await _addToRootWorkspace();
  }

  Future<String> _findParentRootWorkspace() async {
    var parent = await _findParentRootWorkspaceOrNull();
    if (parent == null) {
      throw StateError('Parent workspace not found for $path');
    }
    return parent;
  }

  Future<String?> _findParentRootWorkspaceOrNull() async {
    var parent = dirname(normalize(absolute(path)));
    while (true) {
      try {
        var pubspecMap = await pathGetPubspecYamlMap(parent);
        if (pubspecMap.containsKey('workspace')) {
          return parent;
        }
      } catch (_) {}
      var newParent = dirname(parent);
      if (newParent == parent) {
        return null;
      }
      parent = newParent;
    }
  }

  Future<void> _addToRootWorkspace() async {
    var parent = await _findParentRootWorkspace();
    var relativePath = toPosixPath(relative(path, from: parent));
    var pubspecMap = await pathGetPubspecYamlMap(parent);
    var workspace = pubspecMap['workspace'];
    List<String>? newList;
    if (workspace is List) {
      if (workspace.contains(relativePath)) {
        stderr.writeln('$relativePath already in workspace');
        return;
      }

      newList = List<String>.from(workspace)..add(relativePath);
    } else {
      newList = [relativePath];
    }
    var file = File(join(parent, 'pubspec.yaml'));
    var yamlEditor = YamlEditor(await file.readAsString());
    stdout.writeln('Setting $newList to workspace');
    yamlEditor.updateOrAdd(['workspace'], newList);
    await file.writeLinesIfNeeded(yamlEditor.toLines(), verbose: true);
  }

  /// Set "resolution: workspace" in pubspec.yaml
  Future<void> _setWorkspaceResolution(bool on) async {
    var file = File(join(path, 'pubspec.yaml'));
    if (!file.existsSync()) {
      stderr.writeln('$file not found');
    } else {
      var pubspecMap = await pathGetPubspecYamlMap(path);
      var resolution = (pubspecMap['resolution']);
      if (resolution == 'workspace') {
        if (on) {
          stderr.writeln('$file already in workspace');
          return;
        }
      } else {
        if (!on) {
          stderr.writeln('$file already not in workspace');
          return;
        }
      }
      var yamlEditor = YamlEditor(await file.readAsString());
      if (on) {
        yamlEditor.updateOrAdd(['resolution'], 'workspace');
      } else {
        yamlEditor.remove(['resolution']);
      }
      await file.writeLinesIfNeeded(yamlEditor.toLines(), verbose: true);
    }
  }

  /// Add all projects (inner directories) to workspace
  /// if [keepExistingWorkspaceResolution] is true, only add existing projects with already a
  /// workspace resolution
  Future<void> addAllProjectsToWorkspace({
    bool? keepExistingWorkspaceResolution,
  }) async {
    var normalizedPath = normalize(absolute(path));

    Future<void> recurse(String dirPath) async {
      Stream<FileSystemEntity> stream;
      try {
        stream = Directory(dirPath).list(followLinks: false);
      } catch (_) {
        return;
      }
      await for (var entity in stream) {
        if (entity is Directory) {
          var name = basename(entity.path);
          if (_isToBeIgnored(name)) {
            continue;
          }
          var subPath = entity.path;
          if (normalize(absolute(subPath)) == normalizedPath) {
            continue;
          }
          var pubspecFile = File(join(subPath, 'pubspec.yaml'));
          if (pubspecFile.existsSync()) {
            try {
              var pubIoPackage = PubIoPackage(subPath);
              await pubIoPackage.ready;
              if (pubIoPackage.isWorkspace) {
                // Don't add the project if it is workspace itself and skip going down the tree
                stdout.writeln(
                  'Skipping project as it is a workspace itself: $subPath',
                );
                continue;
              }
              if (keepExistingWorkspaceResolution ?? false) {
                if (!pubIoPackage.hasWorkspaceResolution) {
                  stdout.writeln(
                    'Skipping project without workspace resolution: $subPath',
                  );
                  await recurse(subPath);
                  continue;
                }
              }
              var dtkProject = DtkProject(subPath);
              await dtkProject.addToWorkspace();
            } catch (e) {
              stderr.writeln('Error checking project $subPath: $e');
            }
          }
          await recurse(subPath);
        }
      }
    }

    await recurse(path);
  }


  /// Add all projects (inner directories) to workspace
  Future<void> clearDependencyOverrides() async {
    var depOverridePath = join(path, 'pubspec_overrides.yaml');
    if (File(depOverridePath).existsSync()) {
      stdout.writeln('Deleting $depOverridePath');
      await File(depOverridePath).delete();
    }
    var prj = PubIoPackage(path);
    await prj.ready;
    var dofPub = prj.dofPub;
    var localPubspecMap = prj.pubspecYaml;
    var overrides = localPubspecMap['dependency_overrides'];
    if (overrides is Map) {
      var keys = overrides.keys.map((e) => e.toString());
      var shell = Shell(workingDirectory: path, verbose: true);
      stdout.writeln('Removing overrides: ${keys.join(', ')}');
      await shell.run(
        '$dofPub remove ${keys.map((key) => 'override:$key').join(' ')}',
      );
    }
  }

  /// Add all projects (inner directories) to workspace
  Future<void> clearSubProjectsDependencyOverrides() async {
    /// Safe compare
    var normalizedPath = normalize(absolute(path));
    await recursiveActions(
      [path],
      action: (path) async {
        if (normalize(absolute(path)) == normalizedPath) {
          return;
        }
        var dtkProject = DtkProject(path);
        await dtkProject.clearDependencyOverrides();
      },
    );
  }

  static bool _isToBeIgnored(String baseName) {
    if (baseName.startsWith('.')) {
      return true;
    }
    return _blackListedTargets.contains(baseName);
  }

  static final _blackListedTargets = <String>{
    'build',
    'deploy',
    'node_modules',
  };
}
