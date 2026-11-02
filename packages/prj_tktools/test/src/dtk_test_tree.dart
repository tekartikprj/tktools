import 'dart:io';

import 'package:path/path.dart';
import 'package:tekartik_prj_tktools/dtk.dart'
    show DbDtkGitRepository, DtkGitConfigDbExt, dtkGitConfigDbAction;
import 'package:tekartik_prj_tktools/tkpub.dart'
    show TkPubConfigDbExt, TkPubDbPackage, tkPubDbAction;

/// A temp git top and the two registry exports describing it.
///
/// - `github.com/tekartik/cv.dart`: cloned (`.git`), package `cv` (pub.dev)
///   in `packages/cv`, tags main + public.
/// - `github.com/tekartik/sembast.dart`: cloned without `.git`, package
///   `sembast` registered but its folder is empty, tag public.
/// - `github.com/fork/cv.dart`: registered, not cloned, omitted.
/// - `github.com/tekartik/missing.dart`: registered, not cloned.
/// - `github.com/other/unregistered`: a checkout that is not registered.
/// - package `bad`: an unusable git url.
class DtkTestTree {
  /// Root temp dir.
  final Directory tmp;

  /// The git top.
  String get gitTop => join(tmp.path, 'git');

  /// The dtk git registry export.
  String get gitExport => join(tmp.path, 'dtk_git.jsonl');

  /// The tkpub registry export.
  String get pubExport => join(tmp.path, 'tkpub.jsonl');

  DtkTestTree._(this.tmp);

  /// Path in the git top.
  String gitTopPath(String relativePath) =>
      normalize(join(gitTop, joinAll(url.split(relativePath))));

  /// Create the tree and the exports.
  static Future<DtkTestTree> create() async {
    var tree = DtkTestTree._(
      await Directory.systemTemp.createTemp('dtk_registry_'),
    );
    for (var dir in [
      'github.com/tekartik/cv.dart/.git',
      'github.com/tekartik/cv.dart/packages/cv',
      'github.com/tekartik/sembast.dart',
      'github.com/other/unregistered/.git',
    ]) {
      await Directory(tree.gitTopPath(dir)).create(recursive: true);
    }
    await File(
      tree.gitTopPath('github.com/tekartik/cv.dart/packages/cv/pubspec.yaml'),
    ).writeAsString('name: cv\n');

    DbDtkGitRepository repo(String gitUrl, {List<String>? tags, bool? omit}) =>
        DbDtkGitRepository()
          ..gitUrl.v = gitUrl
          ..tags.setValue(tags)
          ..omit.setValue(omit);
    await dtkGitConfigDbAction<void>(
      (db) async {
        await db.setRepository(
          repo('https://github.com/tekartik/cv.dart', tags: ['public', 'main']),
        );
        await db.setRepository(
          repo('git@github.com:tekartik/sembast.dart.git', tags: ['public']),
        );
        await db.setRepository(
          repo('https://github.com/fork/cv.dart', omit: true),
        );
        await db.setRepository(
          repo('https://github.com/tekartik/missing.dart'),
        );
      },
      write: true,
      configExportPath: tree.gitExport,
    );
    await tkPubDbAction<void>(
      (db) async {
        await db.setPackage(
          'cv',
          TkPubDbPackage()
            ..gitUrl.v = 'https://github.com/tekartik/cv.dart'
            ..gitPath.v = 'packages/cv'
            ..published.v = 'hosted',
        );
        await db.setPackage(
          'sembast',
          TkPubDbPackage()
            ..gitUrl.v = 'git@github.com:tekartik/sembast.dart.git'
            ..gitPath.v = 'sembast',
        );
        await db.setPackage('bad', TkPubDbPackage()..gitUrl.v = 'x');
      },
      write: true,
      configExportPath: tree.pubExport,
    );
    return tree;
  }

  /// Delete the tree.
  Future<void> delete() => tmp.delete(recursive: true);
}
