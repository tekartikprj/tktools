import 'package:args/args.dart';
// ignore: implementation_imports
import 'package:process_run/src/mixin/shell_bin.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub.dart';
import 'package:tekartik_prj_tktools/src/tkpub_db.dart';

/// git url option
const optionGitUrl = 'git-url';

/// git path option
const optionGitPath = 'git-path';

/// git ref option
const optionGitRef = 'git-ref';

/// tkpub config
class TkPubConfigCommand extends TkPubSubCommand {
  /// tkpub config
  TkPubConfigCommand() : super(name: 'config') {
    addCommand(_SetCommand());
    addCommand(_GetCommand());
    addCommand(_DeleteCommand());
    addCommand(_SetRefCommand());
    addCommand(_GetRefCommand());
    addCommand(_ListCommand());
    addCommand(_GetExportPathCommand());
  }
}

abstract class _TkPubConfigSubCommand extends ShellBinCommand {
  TkPubConfigCommand get tkPubConfigCommand => parent as TkPubConfigCommand;
  _TkPubConfigSubCommand({required super.name, super.parser}) : super();
}

class _DeleteCommand extends _TkPubConfigSubCommand {
  _DeleteCommand()
    : super(name: 'delete', parser: ArgParser(allowTrailingOptions: true));

  @override
  FutureOr<bool> onRun() async {
    var rest = results.rest;
    if (rest.length != 1) {
      throw ArgumentError('One argument expected (package name)');
    }

    var packageName = rest.first;
    await tkPubConfigCommand.dbAction((db) async {
      await db.deletePackage(packageName);
    }, write: true);
    return true;
  }
}

class _SetCommand extends _TkPubConfigSubCommand {
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
    await tkPubConfigCommand.dbAction((db) async {
      var package =
          tkPubPackagesStore.record(packageName).cv()
            ..gitUrl.v = gitUrl
            ..gitPath.setValue(gitPath)
            ..gitRef.setValue(gitRef);
      await db.setPackage(package.id, package);
      writePackageConfig(package);
    }, write: true);
    return true;
  }
}

class _GetCommand extends _TkPubConfigSubCommand {
  _GetCommand()
    : super(name: 'get', parser: ArgParser(allowTrailingOptions: true));

  @override
  FutureOr<bool> onRun() async {
    var rest = results.rest;
    if (rest.length != 1) {
      throw ArgumentError('One argument expected (package name)');
    }
    var packageName = rest.first;

    await tkPubConfigCommand.dbAction((db) async {
      var package = await db.getPackage(packageName);
      stdout.writeln(
        '${package.id} ${package.gitUrl.v}${package.gitPath.isNotNull ? ' ${package.gitPath.v}' : ''}${package.gitRef.isNotNull ? ' ${package.gitRef.v}' : ''}',
      );
    });
    return true;
  }
}

/// Write package config
void writePackageConfig(TkPubDbPackage package) {
  stdout.writeln(
    '${package.id} ${package.gitUrl.v}${package.gitPath.isNotNull ? ' ${package.gitPath.v}' : ''}${package.gitRef.isNotNull ? ' ${package.gitRef.v}' : ''}',
  );
}

class _ListCommand extends _TkPubConfigSubCommand {
  _ListCommand()
    : super(name: 'list', parser: ArgParser(allowTrailingOptions: true));

  @override
  FutureOr<bool> onRun() async {
    await tkPubConfigCommand.dbAction((db) async {
      var packages = await tkPubPackagesStore.query().getRecords(db.db);
      for (var package in packages) {
        stdout.writeln(
          '${package.id} ${package.gitUrl.v}${package.gitPath.isNotNull ? ' ${package.gitPath.v}' : ''}${package.gitRef.isNotNull ? ' ${package.gitRef.v}' : ''}',
        );
      }
    });
    return true;
  }
}

class _SetRefCommand extends _TkPubConfigSubCommand {
  _SetRefCommand()
    : super(name: 'set-ref', parser: ArgParser(allowTrailingOptions: true));

  @override
  FutureOr<bool> onRun() async {
    var rest = results.rest;
    if (rest.length != 1) {
      throw ArgumentError('One argument expected (ref name)');
    }

    await tkPubConfigCommand.dbAction((db) async {
      var ref = tkPubConfigRefRecord.cv()..gitRef.v = rest.first;
      await ref.put(db.db);
    }, write: true);
    return true;
  }
}

class _GetRefCommand extends _TkPubConfigSubCommand {
  _GetRefCommand()
    : super(name: 'get-ref', parser: ArgParser(allowTrailingOptions: true));

  @override
  FutureOr<bool> onRun() async {
    var gitRef = await tkPubConfigCommand.dbAction((db) async {
      var config = await tkPubConfigRefRecord.get(db.db);
      return config?.gitRef.v;
    });
    stdout.writeln(gitRef ?? '<none>');
    return true;
  }
}

class _GetExportPathCommand extends _TkPubConfigSubCommand {
  _GetExportPathCommand()
    : super(
        name: 'get-export-path',
        parser: ArgParser(allowTrailingOptions: true),
      );

  @override
  FutureOr<bool> onRun() async {
    var configExportPath = await tkPubConfigCommand.getConfigExportPath();
    stdout.writeln(configExportPath ?? '<none>');
    return true;
  }
}
