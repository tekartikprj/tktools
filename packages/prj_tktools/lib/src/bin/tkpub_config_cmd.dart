import 'package:args/args.dart';
// ignore: implementation_imports
import 'package:process_run/src/mixin/shell_bin.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/tkpub_db.dart';

/// git url option
const optionGitUrl = 'git-url';

/// git path option
const optionGitPath = 'git-path';

/// git ref option
const optionGitRef = 'git-ref';

/// tkpub config
class TkpubConfigCommand extends ShellBinCommand {
  /// tkpub config
  TkpubConfigCommand() : super(name: 'config') {
    addCommand(_SetCommand());
    addCommand(_GetCommand());
    addCommand(_DeleteCommand());
    addCommand(_SetRefCommand());
    addCommand(_ListCommand());
  }
}

class _DeleteCommand extends ShellBinCommand {
  _DeleteCommand()
      : super(name: 'delete', parser: ArgParser(allowTrailingOptions: true));

  @override
  FutureOr<bool> onRun() async {
    var rest = results.rest;
    if (rest.length != 1) {
      throw ArgumentError('One argument expected (package name)');
    }

    var packageName = rest.first;
    await tkPubDbAction((db) async {
      await db.deletePackage(packageName);
    }, write: true);
    return true;
  }
}

class _SetCommand extends ShellBinCommand {
  _SetCommand()
      : super(name: 'set', parser: ArgParser(allowTrailingOptions: true)) {
    parser.addOption(optionGitUrl, help: 'Git url');
    parser.addOption(optionGitPath, help: 'Git path');
    parser.addOption(optionGitRef, help: 'Git ref');
  }

  @override
  FutureOr<bool> onRun() async {
    var gitUrl = results[optionGitUrl] as String?;
    var gitPath = results[optionGitPath] as String?;
    var gitRef = results[optionGitRef] as String?;
    if (gitUrl == null) {
      throw ArgumentError('git-url is required');
    }
    var rest = results.rest;
    if (rest.length != 1) {
      throw ArgumentError('One argument expected (package name)');
    }

    var packageName = rest.first;
    await tkPubDbAction((db) async {
      var package = tkPubPackagesStore.record(packageName).cv()
        ..gitUrl.v = gitUrl
        ..gitPath.setValue(gitPath)
        ..gitRef.setValue(gitRef);
      await db.setPackage(package);
      writePackageConfig(package);
    }, write: true);
    return true;
  }
}

class _GetCommand extends ShellBinCommand {
  _GetCommand()
      : super(name: 'get', parser: ArgParser(allowTrailingOptions: true));

  @override
  FutureOr<bool> onRun() async {
    var rest = results.rest;
    if (rest.length != 1) {
      throw ArgumentError('One argument expected (package name)');
    }
    var packageName = rest.first;

    await tkPubDbAction((db) async {
      var package = await db.getPackage(packageName);
      stdout.writeln(
          '${package.id} ${package.gitUrl.v}${package.gitPath.isNotNull ? ' ${package.gitPath.v}' : ''}${package.gitRef.isNotNull ? ' ${package.gitRef.v}' : ''}');
    });
    return true;
  }
}

/// Write package config
void writePackageConfig(TkPubDbPackage package) {
  stdout.writeln(
      '${package.id} ${package.gitUrl.v}${package.gitPath.isNotNull ? ' ${package.gitPath.v}' : ''}${package.gitRef.isNotNull ? ' ${package.gitRef.v}' : ''}');
}

class _ListCommand extends ShellBinCommand {
  _ListCommand()
      : super(name: 'list', parser: ArgParser(allowTrailingOptions: true));

  @override
  FutureOr<bool> onRun() async {
    await tkPubDbAction((db) async {
      var packages = await tkPubPackagesStore.query().getRecords(db.db);
      for (var package in packages) {
        stdout.writeln(
            '${package.id} ${package.gitUrl.v}${package.gitPath.isNotNull ? ' ${package.gitPath.v}' : ''}${package.gitRef.isNotNull ? ' ${package.gitRef.v}' : ''}');
      }
    });
    return true;
  }
}

class _SetRefCommand extends ShellBinCommand {
  _SetRefCommand()
      : super(name: 'set-ref', parser: ArgParser(allowTrailingOptions: true));

  @override
  FutureOr<bool> onRun() async {
    var rest = results.rest;
    if (rest.length != 1) {
      throw ArgumentError('One argument expected (ref name)');
    }

    await tkPubDbAction((db) async {
      var ref = tkPubConfigRefRecord.cv()..gitRef.v = rest.first;
      await ref.put(db.db);
    }, write: true);
    return true;
  }
}
