import 'package:tekartik_app_common_prefs/app_prefs_async.dart';

/// Open the prefs
Future<PrefsAsync> openGlobalPrefsPrefs() async {
  //var prefsFactory = getPrefsFactorySembast(packageName: 'com.tekartik.tkreg');
  var prefsFactory = getPrefsAsyncFactory(packageName: 'com.tekartik.tkreg');
  return await prefsFactory.openPreferences('config.prefs');
}
