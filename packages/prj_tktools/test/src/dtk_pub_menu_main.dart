import 'dart:io';

import 'package:dev_build/menu/menu_io.dart';
import 'package:path/path.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk.dart'
    show dtkDepExportPathGlobalPrefsKey;
import 'package:tekartik_prj_tktools/src/dtk/dtk_pub_menu.dart';
import 'package:tekartik_prj_tktools/src/tkpub.dart'
    show tkPubExportPathGlobalPrefsKey;
import 'package:tekartik_prj_tktools/tkreg.dart';

/// The dtk pub menu on the exports of the folder `arguments[0]`, the other
/// arguments typed lines. Run by dtk_pub_menu_test.dart, the user prefs in
/// a temp folder.
Future<void> main(List<String> arguments) async {
  // Never the real prefs.
  if (Platform.environment['TEKARTIK_PROCESS_RUN_USER_APP_DATA_PATH'] == null) {
    throw StateError('TEKARTIK_PROCESS_RUN_USER_APP_DATA_PATH not set');
  }
  var dir = arguments.first;
  var prefs = await openGlobalPrefsPrefs();
  await prefs.setString(
    tkPubExportPathGlobalPrefsKey,
    join(dir, 'tkpub.jsonl'),
  );
  await prefs.setString(
    dtkDepExportPathGlobalPrefsKey,
    join(dir, 'dtk_dep.jsonl'),
  );
  mainMenuConsole(arguments.sublist(1), dtkPubMenu);
}
