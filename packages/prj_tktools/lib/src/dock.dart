import 'package:dev_build/shell.dart';
import 'package:path/path.dart';
import 'package:sembast/sembast_io.dart';
import 'package:tekartik_app_dock/prefs.dart';
import 'package:tekartik_prefs_sembast/prefs.dart';
import 'package:tekartik_prefs_sembast/prefs_async.dart';

/// Returns the app-specific data directory for [packageName].
String getDockUserPath({required String packageName}) {
  return join(userAppDataPath, packageName);
}

/// Returns the IO-backed Sembast database factory.
DatabaseFactory getSembastFactory() {
  return databaseFactoryIo;
}

/// Returns a synchronous prefs factory stored in the app data directory.
PrefsFactory getPrefsFactory({required String packageName}) {
  return getPrefsFactorySembast(
    getSembastFactory(),
    getDockUserPath(packageName: packageName),
  );
}

/// Returns an asynchronous prefs factory stored in the app data directory.
PrefsAsyncFactory getPrefsAsyncFactory({required String packageName}) {
  return getPrefsAsyncFactorySembast(
    getSembastFactory(),
    getDockUserPath(packageName: packageName),
  );
}
