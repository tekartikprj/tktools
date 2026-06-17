import 'package:dev_build/menu/menu_io.dart';
import 'package:tekartik_prj_tktools/dtk.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_mixin.dart';

Future<void> main(List<String> args) async {
  mainMenuConsole(args, () {
    dtkMenu();
  });
}
