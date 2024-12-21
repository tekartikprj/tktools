import 'package:dev_build/menu/menu_io.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_prj_menu.dart';

import 'dtk_dep_menu.dart';
import 'dtk_git_menu.dart';

Future<void> main(List<String> args) async {
  mainMenuConsole(args, dtkMenu);
}

/// dtk menu
void dtkMenu() {
  enter(() async {});
  menu('git', () {
    dtkGitMenu();
  });
  menu('dep', () {
    dtkDepMenu();
  });
  menu('prj', () {
    dtkPrjMenu();
  });
}
