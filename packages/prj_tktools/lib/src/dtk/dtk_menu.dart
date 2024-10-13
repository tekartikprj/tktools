import 'package:dev_build/menu/menu_io.dart';
import 'package:dev_build/package.dart';
import 'package:path/path.dart';
// ignore: depend_on_referenced_packages
import 'package:pool/pool.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_git_config_db.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_status_db.dart';
import 'package:tekartik_prj_tktools/src/utils.dart';
import 'package:tekartik_prj_tktools/tkreg.dart';

import 'dtk.dart';

Future<void> main(List<String> args) async {
  mainMenuConsole(args, dtkMenu);
}

DtkStatusDb? _statusDbCached;

/// Get the global status db
Future<DtkStatusDb> getGlobalStatusDb() async {
  return _statusDbCached ??= await dtkStatusDbOpen();
}

/// dtk action runner
abstract class DtkActionRunner<T extends DbDtkAction> {
  /// action name
  final String action;

  /// status db
  final DtkStatusDb db;

  /// run the action
  Future<void> run({bool noReport = false});

  /// find main action
  Future<T> findMainAction({bool noReport = false}) async {
    await _init();
    var dbAction = await db.findOrCreateAction<T>(action);
    if (dbAction.status.v == actionResultOk) {
      if (!noReport) {
        stdout.writeln('action $action already done');
      }
    }
    return dbAction;
  }

  /// Init once
  Future<void> _init() async {
    var concurrency = (await db.getExecutionConcurrency() ?? 1);
    // print('concurrency: $concurrency');
    _poolOrNull ??= Pool(concurrency);
  }

  /// constructor
  DtkActionRunner(this.db, {required this.action});
}

/// dtk find dart project action runner
class DtkDartProjectActionRunner
    extends DtkActionRunner<DbDtkActionPubUpgrade> {
  /// constructor
  DtkDartProjectActionRunner(super.db, {required super.action});

  @override
  Future<void> run({bool noReport = false}) async {
    var mainAction = await findMainAction(noReport: noReport);
    if (mainAction.status.v == actionResultOk) {
      return;
    }
    await DtkFindDartProjectActionRunner(db).run(noReport: true);

    var reposAction = await db.getFindReposAction();
    var gitTop = reposAction.gitTop.v!;
    var repos = reposAction.repos.v!;

    var futures = <Future>[];
    for (var repo in repos) {
      var findDartProjectAction = await db.getFindDartProjectAction(repo: repo);
      for (var path in findDartProjectAction.dartProjects.v!) {
        futures.add(_pool.withResource(() async {
          await shellStdioLinesGrouper.runZoned(() async {
            var dbRepoPath = join(repo, path);
            var projectPath = join(gitTop, dbRepoPath);

            var pubUpgradeAction =
                await db.findOrCreateAction<DbDtkActionPubUpgrade>(action,
                    model: DbDtkActionPubUpgrade()..path.v = dbRepoPath);
            if (pubUpgradeAction.status.v == actionResultOk) {
              return;
            }
            if (action == actionPubUpgrade) {
              await packageRunCi(projectPath,
                  options: PackageRunCiOptions(pubUpgradeOnly: true));
            } else if (action == actionAnalyze) {
              await packageRunCi(projectPath,
                  options:
                      PackageRunCiOptions(analyzeOnly: true, noPubGet: true));
            }

            pubUpgradeAction.status.v = actionResultOk;
            await pubUpgradeAction.put(db.db);
            stdout.writeln(pubUpgradeAction);
          });
        }));
      }
    }
    await Future.wait(futures);
    mainAction.status.v = actionResultOk;
    await mainAction.put(db.db);
    stdout.writeln('action $action done');
  }
}

/// ! (might need decrease)
Pool _pool = Pool(Platform.isLinux || Platform.isMacOS ? 50 : 1);
Pool? _poolOrNull;

/// dtk find dart project action runner
class DtkFindDartProjectActionRunner
    extends DtkActionRunner<DbDtkActionFindDartProject> {
  /// constructor
  DtkFindDartProjectActionRunner(super.db)
      : super(action: actionFindDartProjects);

  @override
  Future<void> run({bool noReport = false}) async {
    var findDartProjectMainAction = await findMainAction(noReport: noReport);
    if (findDartProjectMainAction.status.v == actionResultOk) {
      return;
    }
    await DtkFindReposActionRunner(db).run(noReport: true);

    var reposAction = await db.getFindReposAction();
    var gitTop = reposAction.gitTop.v!;
    var repos = reposAction.repos.v!;

    for (var repo in repos) {
      var findDartProjectAction =
          await db.findOrCreateAction<DbDtkActionFindDartProject>(action,
              filter: Filter.equals(
                  dbDtkActionFindDartProjectModel.repo.name, repo),
              model: DbDtkActionFindDartProject()..repo.v = repo);
      if (findDartProjectAction.status.v == actionResultOk) {
        continue;
      }
      var gitProjectTop = join(gitTop, repo);
      var paths = (await recursivePubPath([gitProjectTop]))
          .map((path) => relative(path, from: gitProjectTop))
          .toList();
      stdout.writeln('repo $repo: $paths');

      findDartProjectAction.dartProjects.v = paths;
      findDartProjectAction.status.v = actionResultOk;
      await findDartProjectAction.put(db.db);
      //write(findDartProject);
    }
    findDartProjectMainAction.status.v = actionResultOk;
    await findDartProjectMainAction.put(db.db);
    stdout.writeln('action $action done');
  }
}

/// dtk find dart project action runner
class DtkFindReposActionRunner extends DtkActionRunner<DbDtkActionFindRepos> {
  /// constructor
  DtkFindReposActionRunner(super.db) : super(action: actionFindRepos);

  @override
  Future<void> run({bool noReport = false}) async {
    var findRepoAction =
        await db.findOrCreateAction<DbDtkActionFindRepos>(action);
    if (findRepoAction.status.v == actionResultOk) {
      if (!noReport) {
        stdout.writeln('find repos already done');
      }
      return;
    }
    var gitTop = await tkPubFindGitTop();
    findRepoAction.gitTop.v = gitTop;

    var repos = await dtkGitGetAllRepositories();
    var foundRepos = <String>[];
    for (var repo in repos) {
      var repoPath = repo.id;
      var path = join(gitTop, repoPath);
      if (Directory(path).existsSync()) {
        foundRepos.add(repoPath);
        write('found repo $path');
      } else {
        write('repo not found at $path');
      }
    }

    /// Ok
    findRepoAction.repos.v = foundRepos;
    findRepoAction.status.v = actionResultOk;

    /// put
    await findRepoAction.put(db.db);
    stdout.writeln('action $action done');
  }
}

/// dtk menu
void dtkMenu() {
  late DtkStatusDb db;
  enter(() async {
    db = await getGlobalStatusDb();
  });
  menu('action', () {
    item('dump actions', () async {
      var list = await dbDtkActionStore.query().getRecords(db.db);
      for (var item in list) {
        write('${item.id} ${item.toMap()}');
      }
    });

    item('findRepos', () async {
      await DtkFindReposActionRunner(db).run();
    });
    item('findDartProject', () async {
      await DtkFindDartProjectActionRunner(db).run();
    });
    item('pubUpgrade', () async {
      await DtkDartProjectActionRunner(db, action: actionPubUpgrade).run();
    });
    item('analyze', () async {
      await DtkDartProjectActionRunner(db, action: actionAnalyze).run();
    });
    item('pubUpgrade && analyze', () async {
      await DtkDartProjectActionRunner(db, action: actionPubUpgrade).run();
      await DtkDartProjectActionRunner(db, action: actionAnalyze).run();
    });
    menu('clear', () async {
      item('clear actions', () async {
        await dbDtkActionStore.delete(db.db);
      });
      for (var action in [
        actionFindDartProjects,
        actionFindRepos,
        actionPubUpgrade,
        actionAnalyze
      ]) {
        item('clear action $action', () async {
          await dbDtkActionStore.delete(db.db,
              finder: Finder(
                  filter: Filter.equals(dbDtkActionModel.action.name, action)));
        });
      }
      item('clear main actions', () async {
        await dbDtkActionStore.delete(db.db,
            finder: Finder(
                filter: Filter.equals(dbDtkActionModel.main.name, true)));
      });
    });
  });
  menu('config', () {
    menu('timepoint', () {
      item('add timepoint', () async {
        var timepoint = await db.createTimepoint();
        write(timepoint);
      });
      Future<void> listTimepoints() async {
        var id = await db.getCurrentTimepointId();
        var list = await db.getTimepoints();
        for (var item in list) {
          write('${id == item.id ? '* ' : '  '}${item.id} ${item.toMap()}');
        }
      }

      item('list timepoints', () async {
        await listTimepoints();
      });
      item('delete timepoint (prompt)', () async {
        await listTimepoints();
        var id = parseInt(await prompt('delete id'));
        if (id != null) {
          var timepoint = await db.getTimepoint(id);
          if (timepoint == null) {
            write('not found');
          } else {
            await db.deleteTimepoint(id);
            write('deleted $timepoint');
          }
        }
      });
      item('delete timepoints (prompt)', () async {
        await listTimepoints();
        var id = parseInt(await prompt('delete before id'));
        if (id != null) {
          var count = await db.deleteTimepoints(beforeId: id);
          write('deleted $count');
        }
      });
      item('get current timepoint id', () async {
        write(await db.getCurrentTimepointId());
      });
      item('get current timepoint', () async {
        write(await db.getCurrentTimepoint());
      });
      item('set current timepoint (prompt)', () async {
        await listTimepoints();
        var id = parseInt(await prompt('set current id'));
        if (id != null) {
          var timepoint = await db.getTimepoint(id);
          if (timepoint == null) {
            write('not found');
          } else {
            await db.setCurrentTimepoint(id);
            write('deleted $timepoint');
          }
        }
      });
    });
    menu('repository', () {
      item('list', () async {
        var list = await dtkGitGetAllRepositories();
        for (var item in list) {
          write('${item.id} ${item.toMap()}');
        }
      });
      item('add by unique name (prompt)', () async {
        var id = await prompt(
            'unique name (example: github.com/tekartik/app_common_utils.dart)');
        if (id != null) {
          await dtkGitConfigDbAction((db) async {
            var repo = await db.getRepositoryOrNull(id);
            if (repo != null) {
              write('already exists $repo');
              write(repo);
              return;
            }
            repo = DbDtkGitRepository()
              ..ref = dtkGitDbRepositoryStore.record(id);
            repo = await db.setRepository(repo);
            write(repo);
          }, write: true);
        }
      });
      item('add (prompt)', () async {
        var url = await prompt('url');
        if (url != null) {
          await dtkGitConfigDbAction((db) async {
            var id = dtkGitUniqueNameFromUrl(url);
            var repo = await db.getRepositoryOrNull(id);
            if (repo != null) {
              write('already exists $repo');
            }
            repo ??= DbDtkGitRepository();
            repo.gitUrl.v = url;
            repo = await db.setRepository(repo);
            write(repo);
          }, write: true);
        }
      });
      item('delete by url (prompt)', () async {
        var url = await prompt('url');
        if (url != null) {
          await dtkGitConfigDbAction((db) async {
            var id = dtkGitUniqueNameFromUrl(url);
            var repo = await db.deleteRepository(id);
            write(repo);
          }, write: true);
        }
      });
      item('delete by id (prompt)', () async {
        var id = await prompt('id');
        if (id != null) {
          await dtkGitConfigDbAction((db) async {
            var repo = await db.deleteRepository(id);
            write(repo);
          }, write: true);
        }
      });
    });
    menu('execution', () async {
      item('get', () async {
        var config = await dbDtkExecutionConfigRecord.get(db.db);
        write(config);
      });
      item('set concurrency (prompt)', () async {
        var config = await dbDtkExecutionConfigRecord.get(db.db);
        write(config);
        var concurrency = parseInt(await prompt('concurrency'));
        if (concurrency != null) {
          config ??= DbDtkExecutionConfig();
          config.concurrency.v = concurrency;
          config = await dbDtkExecutionConfigRecord.put(db.db, config);
          write(config);
          _poolOrNull = null;
        }
      });
    });
    menu('once', () {
      item('get git config path', () async {
        write(await dtkGetGitExportPath());
        var prefs = await openGlobalPrefsPrefs();
        write(prefs.getString(dtkGitExportPathGlobalPrefsKey));
      });
      item('set git config path', () async {
        var prefs = await openGlobalPrefsPrefs();
        write(prefs.getString(dtkGitExportPathGlobalPrefsKey));
        var exportPath = await prompt('export path');
        if (exportPath != null) {
          prefs.setString(
              dtkGitExportPathGlobalPrefsKey, absolute(normalize(exportPath)));
        }
      });
    });
  });
}
