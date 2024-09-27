import 'package:args/args.dart';
import 'package:path/path.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub_config_cmd.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:tekartik_prj_tktools/tkpub_db.dart';

import '../utils.dart';

/// Dev flag

/// Clear
class TkpubSymlinkCommand extends ShellBinCommand {
  /// Clear
  TkpubSymlinkCommand()
      : super(
            name: 'symlink',
            parser: ArgParser(allowTrailingOptions: true),
            description: '''
Symlink multiple packages

tkpub symlink package1 [package2]

tkpub symlink giturl1 [giturl2]
      ''') {
    parser.addFlag(optionGitUrl, help: 'find by git url');
  }

  @override
  FutureOr<bool> onRun() async {
    var path = '.';
    var rawPackages = results.rest;
    if (rawPackages.isEmpty) {
      throw ArgumentError('No package to symlink');
    }
    var allDbPackages = await tkPubDbAction((db) async {
      return await tkPubPackagesStore.query().getRecords(db.db);
    });
    var packages = <String>{};
    for (var rawPackage in rawPackages) {
      for (var dbPackage in allDbPackages) {
        if (dbPackage.id == rawPackage) {
          packages.add(dbPackage.id);
        } else if (dbPackage.gitUrl.v == rawPackage) {
          packages.add(dbPackage.id);
        }
      }
    }
    var dbPackages =
        allDbPackages.where((dbPackage) => (packages.contains(dbPackage.id)));
    var githubTop = normalize(absolute(findGithubTop(path)));
    for (var package in dbPackages) {
      var dependencyPath = joinAll([
        getDependencyGithubPath(
            githubTop: githubTop, gitUrl: package.gitUrl.v!),
        if (package.gitPath.isNotNull) package.gitPath.v!
      ]);
      var dependencyLocalPath = getDependencyLocalPath(
          githubTop: githubTop,
          gitUrl: package.gitUrl.v!,
          gitPath: package.gitPath.v);
      var absoluteLinkPath = normalize(absolute(join(path, dependencyPath)));
      stdout.writeln('${package.id} $dependencyPath');

      var link = Link(absoluteLinkPath);
      try {
        link.deleteSync(recursive: true);
      } catch (_) {}
      Link(absoluteLinkPath).createSync(dependencyLocalPath, recursive: true);
    }

    return true;
  }
}
