import 'package:dev_build/menu/menu_io.dart';
import 'package:dev_build/menu/menu_run_ci.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_prj.dart';

Future<void> main(List<String> args) async {
  mainMenuConsole(args, dtkPrjMenu);
}

/// Prj menu
void dtkPrjMenu() {
  var prj = DtkProject('.');
  menu('project', () {
    item('menu run_ci', () async {
      runCiMenu('.');
    });
    menu('workspace', () {
      item('create workspace root project', () async {
        await prj.createWorkspaceRootProject();
      });
      item('add to workspace', () async {
        await prj.addToWorkspace();
      });
    });
  });
}
