import 'package:cv/cv.dart';
import 'package:dev_build/build_support.dart';
import 'package:process_run/shell.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_prj_tktools/src/tkpub_db.dart';
import 'package:tekartik_prj_tktools/src/utils.dart';
import 'package:tekartik_prj_tktools/tkreg.dart';

/// Prefs key for the git export path
const tkPubExportPathGlobalPrefsKey = 'com.tekartik.tkpub.pubExportPath';

/// Get config export path
Future<String?> tkPubGetConfigExportPath() async {
  var prefs = await openGlobalPrefsPrefs();
  var path = prefs.getString(tkPubExportPathGlobalPrefsKey);
  return path;
}

/// Get local path
Future<String> tkPubGetPackageLocalPath(
    String githubTop, String package) async {
  var dbPackage = await tkPubDbAction((db) => db.getPackage(package));
  return getDependencyLocalPath(
      githubTop: githubTop,
      gitUrl: dbPackage.gitUrl.v!,
      gitPath: dbPackage.gitPath.v);
}

/// Read in the package-config.yaml
Future<Model> tkPubGetPackageConfigMap(String pkgPath) async {
  Model? packageConfigMap;
  try {
    packageConfigMap = await pathGetPackageConfigMap(pkgPath);
  } catch (_) {
    try {
      await Shell(workingDirectory: pkgPath).run('pub get');

      packageConfigMap = await pathGetPubspecYamlMap(pkgPath);
    } catch (e) {
      stderr.writeln('Error: $e failed to get package-config.yaml');
    }
  }
  return packageConfigMap!;
}
