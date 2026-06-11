import 'package:tekartik_prefs/prefs_async.dart';
import 'package:tekartik_prj_tktools/src/dock.dart';

/// Open the prefs
Future<PrefsAsync> openGlobalPrefsPrefs() async {
  //var prefsFactory = getPrefsFactorySembast(packageName: 'com.tekartik.tkreg');
  var prefsFactory = getPrefsAsyncFactory(packageName: 'com.tekartik.tkreg');
  return await prefsFactory.openPreferences('config.prefs');
}
