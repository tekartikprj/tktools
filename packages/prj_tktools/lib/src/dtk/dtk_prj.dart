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
  sdk: ^3.6.0
workspace:
'''.lines;
final _projectPubspec =
    '''
name: {{projectName}}
publish_to: none
environment:
  sdk: ^3.6.0
resolution: workspace
'''.lines;

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
  Future<void> addToWorkspace() async {
    await _lock.synchronized(() async {
      await _addToWorkspace();
    });
  }

  /// Make static for cross project lock
  static final _lock = Lock();

  /// Add current project to workspace
  Future<void> _addToWorkspace() async {
    await _setWorkspaceResolution();
    await _addToRootWorkspace();
  }

  Future<String> _findParentRootWorkspace() async {
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
        throw StateError('Parent workspace not found for $path');
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
  Future<void> _setWorkspaceResolution() async {
    var file = File(join(path, 'pubspec.yaml'));
    if (!file.existsSync()) {
      stderr.writeln('$file not found');
    } else {
      var pubspecMap = await pathGetPubspecYamlMap(path);
      var resolution = (pubspecMap['resolution']);
      if (resolution == 'workspace') {
        stderr.writeln('$file already in workspace');
        return;
      } else if (resolution != null) {
        stderr.writeln('$file already has resolution: $resolution');
        return;
      }
      var yamlEditor = YamlEditor(await file.readAsString());
      yamlEditor.updateOrAdd(['resolution'], 'workspace');
      await file.writeLinesIfNeeded(yamlEditor.toLines(), verbose: true);
    }
  }

  /// Add all projects (inner directories) to workspace
  Future<void> addAllProjectsToWorkspace() async {
    /// Safe compare
    var normalizedPath = normalize(absolute(path));
    await recursiveActions(
      [path],
      action: (path) async {
        if (normalize(absolute(path)) == normalizedPath) {
          return;
        }
        var dtkProject = DtkProject(path);
        await dtkProject.addToWorkspace();
      },
    );
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
      var keys = overrides.keys.map((e) => toString());
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
}
