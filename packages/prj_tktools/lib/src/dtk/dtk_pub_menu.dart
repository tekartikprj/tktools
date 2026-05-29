import 'dart:io';

import 'package:dev_build/menu/menu_io.dart';

import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_dep_config_db.dart';
import 'package:tekartik_prj_tktools/src/tkpub_db.dart';
import 'package:tekartik_prj_tktools/src/utils.dart';
import 'package:tekartik_prj_tktools/tkpub.dart';

Future<void> main(List<String> args) async {
  mainMenuConsole(args, dtkPubMenu);
}

/// Dep menu
void dtkPubMenu() {
  menu('gitRef', () {
    item('get', () async {
      await tkPubDbAction((db) async {
        var config = await db.getConfig();
        write(config);
      }, verbose: true);
    });
    item('set ref (prompt)', () async {
      var config =
          await tkPubDbAction((db) async {
            return await db.getConfig();
          }) ??
          TkPubDbConfigRef();
      var newRef = await prompt('ref (default: ${config.gitRef.v})');
      if (newRef.isNotEmpty) {
        config.gitRef.v = newRef;
        await dtkDepConfigDbAction(
          (db) async {
            await db.setConfig(config);
          },
          write: true,
          verbose: true,
        );
      }
    });
  });

  menu('packages', () {
    item('list', () async {
      var packages = await tkPubGetAllPackages();
      for (var package in packages) {
        writeln(package);
      }
    });
    item('add', () async {
      var package = await prompt('Package name');
      var gitUrl = await prompt('gitUrl');
      var gitPath = await prompt('gitPath');
      await tkPubDbAction((db) async {
        var newPackage = TkPubDbPackage()
          ..gitUrl.v = gitUrl
          ..gitPath.setValue(gitPath.isEmpty ? null : gitPath);
        await db.setPackage(package, newPackage);
      });
    });
    item('check local dirs', () async {
      var gitTop = await tkPubFindGithubTop();
      var packages = await tkPubGetAllPackages();
      for (var package in packages) {
        var packageName = package.packageName;
        var path = getDependencyLocalPath(
          githubTop: gitTop,
          gitUrl: package.gitUrl.v!,
          gitPath: package.gitPath.v,
        );
        var exists = Directory(path).existsSync();
        if (!exists) {
          writeln('Missing local $packageName ($package)');
          writeln('$path: $exists');
        }
      }
    });
  });
}
