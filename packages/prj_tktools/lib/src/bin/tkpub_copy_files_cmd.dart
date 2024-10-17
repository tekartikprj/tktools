import 'package:args/args.dart';
import 'package:path/path.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub.dart';
import 'package:tekartik_prj_tktools/tkpub.dart';

import '../utils.dart';

/// Destination dir
const optionDestinationDir = 'dir';

/// Clear
class TkPubCopyFilesCommand extends TkPubSubCommand {
  /// Clear
  TkPubCopyFilesCommand()
      : super(
            name: 'copy_files',
            parser: ArgParser(allowTrailingOptions: true),
            description: '''
Copy file from package

tkpub copy_files package file1 [file2 file3...] [--dir destination_dir]
      ''') {
    parser.addOption(optionDestinationDir,
        help: 'Output folder', defaultsTo: join('lib', 'src', 'imported'));
  }

  @override
  FutureOr<bool> onRun() async {
    var path = '.';
    var rest = results.rest;
    if (rest.isEmpty) {
      printUsage();
      throw ArgumentError('No package specified');
    }
    var packageName = rest.first;
    var files = rest.sublist(1);
    if (files.isEmpty) {
      printUsage();
      throw ArgumentError('No file specified');
    }
    var package = await dbAction((db) async {
      return await db.getPackage(packageName);
    });
    var githubTop = normalize(absolute(findGithubTop(path)));

    var dependencyLocalPath = getDependencyLocalPath(
        githubTop: githubTop,
        gitUrl: package.gitUrl.v!,
        gitPath: package.gitPath.v);
    stdout.writeln('${package.id} $dependencyLocalPath');

    var destinationDir = results.option(optionDestinationDir)!;
    var dirEnsured = false;
    void ensureDir() {
      if (!dirEnsured) {
        var dir = Directory(destinationDir);
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        dirEnsured = true;
      }
    }

    for (var file in files) {
      var sourceFile = join(dependencyLocalPath, file);
      var ioFile = File(sourceFile);
      if (!ioFile.existsSync()) {
        throw StateError('File not found: $sourceFile');
      }
      ensureDir();
      await ioFile.copy(join(destinationDir, basename(sourceFile)));
    }

    /*
    var packages = <String>{};
    for (var rawPackage in rest) {
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
    */
    return true;
  }
}
