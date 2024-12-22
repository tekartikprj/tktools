import 'package:dev_build/menu/menu_io.dart';
import 'package:dev_build/menu/menu_run_ci.dart';
import 'package:path/path.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_prj.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:tekartik_sc/git.dart';

Future<void> main(List<String> args) async {
  mainMenuConsole(args, dtkPrjMenu);
}

/// Prj menu
void dtkPrjMenu({String? path}) {
  path ??= '.';
  _dtkPrjMenu(path: path);
}

/// Prj menu
void _dtkPrjMenu({required String path}) {
  var prj = DtkProject(path);
  menu('project at $path (${normalize(absolute(path))}', () {
    enter(() async {
      var dtkProject = PubIoPackage(path);
      try {
        await dtkProject.ready;
        write('path: $path');
        write('isWorkspace: ${dtkProject.isWorkspace}');
        write('isFlutter: ${dtkProject.isFlutter}');
        try {
          write('workPath: ${await pathGetResolvedWorkPath(path)}');
        } catch (e) {
          write('workPath error: $e');
        }
      } catch (e) {
        write('not a dart project, error: $e');
      }
    });
    item('menu run_ci', () async {
      runCiMenu('.');
    });
    menu('workspace', () {
      item('status', () async {
        var dtkProject = PubIoPackage(path);
        await dtkProject.ready;
        write('path: $path');
        write('git path: . ${await findGitTopLevelPath(path)}');
        write('isWorkspace: ${dtkProject.isWorkspace}');
        write('isFlutter: ${dtkProject.isFlutter}');
        try {
          write('workPath: ${await pathGetResolvedWorkPath(path)}');
        } catch (e) {
          write('workPath error: $e');
        }
      });
      item('create workspace root project', () async {
        await prj.createWorkspaceRootProject();
      });
      item('create workspace root project and add sub project to root',
          () async {
        await prj.createWorkspaceRootProject();
        await prj.addAllProjectsToWorkspace();
      });
      item('add to workspace', () async {
        await prj.addToWorkspace();
      });
      item('add all projects to workspace', () async {
        await prj.addAllProjectsToWorkspace();
      });
    });
  });
  item('push directory (prompt)', () async {
    var newPath = await prompt('path (default: $path)');
    if (newPath.isNotEmpty) {
      await showMenu(() {
        _dtkPrjMenu(path: newPath);
      });
      write('back to $path');
    }
  });
}
