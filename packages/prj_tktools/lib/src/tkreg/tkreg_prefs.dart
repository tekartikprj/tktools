import 'package:tekartik_app_common_prefs/app_prefs.dart';

/// Open the prefs
Future<Prefs> openGlobalPrefsPrefs() async {
  var prefsFactory = getPrefsFactory(packageName: 'com.tekartik.tkreg');
  return await prefsFactory.openPreferences('config.prefs');
}
