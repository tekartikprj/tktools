import 'package:tekartik_prj_tktools/src/tkpub_db.dart';
import 'package:tekartik_prj_tktools/src/utils.dart';

/// Get local path
Future<String> tkPubGetPackageLocalPath(
    String githubTop, String package) async {
  var dbPackage = await tkPubDbAction((db) => db.getPackage(package));
  return getDependencyLocalPath(
      githubTop: githubTop,
      gitUrl: dbPackage.gitUrl.v!,
      gitPath: dbPackage.gitPath.v);
}

/// Get config export path
Future<String?> tkPubGetConfigExportPath() async {
  var prefs = await openPrefs();
  var configExportPath = prefs.getString(prefsKeyConfigExportPath);
  return configExportPath;
}
