import 'package:dev_build/menu/menu_io.dart';
import 'package:dev_build/package.dart';
import 'package:path/path.dart';
// ignore: depend_on_referenced_packages
import 'package:pool/pool.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_common_utils/string_utils.dart';
import 'package:tekartik_common_utils/tags.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_git_config_db.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_status_db.dart';
import 'package:tekartik_prj_tktools/src/utils.dart';
import 'package:tekartik_prj_tktools/tkreg.dart';

import 'dtk.dart';

Future<void> main(List<String> args) async {
  mainMenuConsole(args, dtkGitMenu);
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

  /// Creates a [DtkActionRunner] with [db] database and [action].
  DtkActionRunner(this.db, {required this.action});
}

/// Status of one dart project for a given action.
class DtkActionProjectStatus {
  /// repo/dartProjectPath (relative to the git top)
  final String path;

  /// [actionResultNone], [actionResultOk] or [actionResultKo]
  final String status;

  /// Creates a [DtkActionProjectStatus].
  DtkActionProjectStatus({required this.path, required this.status});

  /// True if the project has been done (or manually validated)
  bool get isOk => status == actionResultOk;

  @override
  String toString() => '[$status] $path';
}

/// dtk find dart project action runner
class DtkDartProjectActionRunner
    extends DtkActionRunner<DbDtkActionPubUpgrade> {
  /// Creates a [DtkDartProjectActionRunner] with [db] database and [action].
  DtkDartProjectActionRunner(super.db, {required super.action});

  /// All the dart project paths (relative to the git top) of the current
  /// timepoint, empty if `findDartProject` has not been run yet.
  Future<List<String>> getDartProjectPaths() async {
    var findDartProjectAction = await DtkFindDartProjectActionRunner(
      db,
    ).findMainAction(noReport: true);
    if (findDartProjectAction.status.v != actionResultOk) {
      return <String>[];
    }
    var reposAction = await db.getFindReposAction();
    var paths = <String>[];
    for (var repo in reposAction.repos.v!) {
      var repoAction = await db.getFindDartProjectAction(repo: repo);
      for (var path in repoAction.dartProjects.v!) {
        paths.add(join(repo, path));
      }
    }
    return paths;
  }

  /// Status of each dart project for this action.
  Future<List<DtkActionProjectStatus>> getProjectStatuses() async {
    var subActions = await db.findSubActions<DbDtkActionPubUpgrade>(action);
    var statusMap = <String, String>{
      for (var subAction in subActions)
        if (subAction.path.v != null)
          subAction.path.v!: subAction.status.v ?? actionResultNone,
    };
    return (await getDartProjectPaths())
        .map(
          (path) => DtkActionProjectStatus(
            path: path,
            status: statusMap[path] ?? actionResultNone,
          ),
        )
        .toList();
  }

  /// Projects not done yet (never run or failed).
  Future<List<DtkActionProjectStatus>> getRemainingProjects() async {
    return (await getProjectStatuses())
        .where((status) => !status.isOk)
        .toList();
  }

  /// Write the remaining projects, returns them.
  Future<List<DtkActionProjectStatus>> writeRemaining() async {
    var statuses = await getProjectStatuses();
    if (statuses.isEmpty) {
      write('no dart project found, run findDartProject first');
      return <DtkActionProjectStatus>[];
    }
    var remaining = statuses.where((status) => !status.isOk).toList();
    write(
      '$action: ${statuses.length - remaining.length}/${statuses.length} '
      'done, ${remaining.length} remaining',
    );
    for (var (index, status) in remaining.indexed) {
      write('${index + 1} $status');
    }
    return remaining;
  }

  /// Force the status of a project to [actionResultOk].
  Future<void> markProjectDone(String path) async {
    var projectAction = await db.findOrCreateAction<DbDtkActionPubUpgrade>(
      action,
      model: DbDtkActionPubUpgrade()..path.v = path,
    );
    projectAction.status.v = actionResultOk;
    await projectAction.put(db.db);
    write('marked done $projectAction');
  }

  /// Mark the main action done when all the projects are done.
  ///
  /// Returns true if the main action is done.
  Future<bool> updateMainActionStatus({bool noReport = false}) async {
    var statuses = await getProjectStatuses();
    if (statuses.isEmpty) {
      if (!noReport) {
        stdout.writeln('action $action: no dart project found');
      }
      return false;
    }
    var remaining = statuses.where((status) => !status.isOk).toList();
    if (remaining.isNotEmpty) {
      if (!noReport) {
        stdout.writeln(
          'action $action: ${remaining.length} project(s) remaining',
        );
      }
      return false;
    }
    var mainAction = await findMainAction(noReport: true);
    if (mainAction.status.v != actionResultOk) {
      mainAction.status.v = actionResultOk;
      await mainAction.put(db.db);
    }
    if (!noReport) {
      stdout.writeln('action $action done');
    }
    return true;
  }

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

    var failed = <String>[];
    var futures = <Future>[];
    for (var repo in repos) {
      var findDartProjectAction = await db.getFindDartProjectAction(repo: repo);
      for (var path in findDartProjectAction.dartProjects.v!) {
        futures.add(
          _pool.withResource(() async {
            await shellStdioLinesGrouper.runZoned(() async {
              var dbRepoPath = join(repo, path);
              var projectPath = join(gitTop, dbRepoPath);

              var pubUpgradeAction = await db
                  .findOrCreateAction<DbDtkActionPubUpgrade>(
                    action,
                    model: DbDtkActionPubUpgrade()..path.v = dbRepoPath,
                  );
              if (pubUpgradeAction.status.v == actionResultOk) {
                return;
              }
              try {
                if (action == actionPubUpgrade) {
                  await packageRunCi(
                    projectPath,
                    options: PackageRunCiOptions(pubUpgradeOnly: true),
                  );
                } else if (action == actionAnalyze) {
                  await packageRunCi(
                    projectPath,
                    options: PackageRunCiOptions(
                      analyzeOnly: true,
                      noPubGet: true,
                    ),
                  );
                }
                pubUpgradeAction.status.v = actionResultOk;
              } catch (e) {
                failed.add(dbRepoPath);
                pubUpgradeAction.status.v = actionResultKo;
                stderr.writeln('$action failed on $dbRepoPath: $e');
              }

              await pubUpgradeAction.put(db.db);
              stdout.writeln(pubUpgradeAction);
            });
          }),
        );
      }
    }
    await Future.wait(futures);
    if (failed.isNotEmpty) {
      stdout.writeln('$action failed on ${failed.length} project(s):');
      for (var path in failed..sort()) {
        stdout.writeln('  $path');
      }
      stdout.writeln(
        'fix them and run $action again, or validate them in the '
        '"remaining" menu',
      );
    }
    await updateMainActionStatus();
  }
}

/// ! (might need decrease)
Pool _pool = Pool(Platform.isLinux || Platform.isMacOS ? 50 : 1);
Pool? _poolOrNull;

/// dtk find dart project action runner
class DtkFindDartProjectActionRunner
    extends DtkActionRunner<DbDtkActionFindDartProject> {
  /// Creates a [DtkFindDartProjectActionRunner] with [db] database.
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
    var timepoint = await db.getCurrentTimepoint();
    stdout.writeln('timepoint: $timepoint');
    for (var repo in repos) {
      var findDartProjectAction = await db
          .findOrCreateAction<DbDtkActionFindDartProject>(
            action,
            filter: Filter.equals(
              dbDtkActionFindDartProjectModel.repo.name,
              repo,
            ),
            model: DbDtkActionFindDartProject()..repo.v = repo,
          );
      if (findDartProjectAction.status.v == actionResultOk) {
        continue;
      }
      var gitProjectTop = join(gitTop, repo);
      var paths = (await recursivePubPath(
        [gitProjectTop],
        dependencies: timepoint?.dependencies.v,
        readConfig: true,
      )).map((path) => relative(path, from: gitProjectTop)).toList();
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
  /// Creates a [DtkFindReposActionRunner] with [db] database.
  DtkFindReposActionRunner(super.db) : super(action: actionFindRepos);

  @override
  Future<void> run({bool noReport = false}) async {
    var findRepoAction = await db.findOrCreateAction<DbDtkActionFindRepos>(
      action,
    );
    if (findRepoAction.status.v == actionResultOk) {
      if (!noReport) {
        stdout.writeln('find repos already done');
      }
      return;
    }
    var gitTop = await tkPubFindGitTop();
    findRepoAction.gitTop.v = gitTop;

    var timepoint = await db.getCurrentTimepoint();
    stdout.writeln('timepoint: $timepoint');
    var repos = await dtkGitGetAllRepositories(
      tagFilter: timepoint?.tagFilter.v,
    );
    var foundRepos = <String>[];
    for (var repo in repos) {
      if (repo.omit.v ?? false) {
        continue;
      }
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
void dtkGitMenu() {
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
    menu('remaining', () {
      for (var projectAction in [actionPubUpgrade, actionAnalyze]) {
        item('list remaining $projectAction', () async {
          await DtkDartProjectActionRunner(
            db,
            action: projectAction,
          ).writeRemaining();
        });
        item('mark done $projectAction (prompt)', () async {
          var runner = DtkDartProjectActionRunner(db, action: projectAction);
          var remaining = await runner.writeRemaining();
          if (remaining.isEmpty) {
            return;
          }
          var answer = (await prompt(
            'mark done (index list, "ko" for all failed, "all", '
            'empty to cancel)',
          )).trim();
          var selection = <DtkActionProjectStatus>[];
          if (answer.nonEmpty() == null) {
            return;
          } else if (answer == 'all') {
            selection = remaining;
          } else if (answer == actionResultKo) {
            selection = remaining
                .where((status) => status.status == actionResultKo)
                .toList();
          } else {
            for (var part in answer.split(',')) {
              var index = parseInt(part.trim());
              if (index == null || index < 1 || index > remaining.length) {
                write('invalid index $part');
                return;
              }
              selection.add(remaining[index - 1]);
            }
          }
          if (selection.isEmpty) {
            write('nothing selected');
            return;
          }
          for (var status in selection) {
            await runner.markProjectDone(status.path);
          }
          await runner.updateMainActionStatus();
        });
      }
    });
    menu('clear', () async {
      item('clear actions', () async {
        await dbDtkActionStore.delete(db.db);
      });
      for (var action in [
        actionFindDartProjects,
        actionFindRepos,
        actionPubUpgrade,
        actionAnalyze,
      ]) {
        item('clear action $action', () async {
          await dbDtkActionStore.delete(
            db.db,
            finder: Finder(
              filter: Filter.equals(dbDtkActionModel.action.name, action),
            ),
          );
        });
      }
      item('clear main actions', () async {
        await dbDtkActionStore.delete(
          db.db,
          finder: Finder(
            filter: Filter.equals(dbDtkActionModel.main.name, true),
          ),
        );
      });
    });
  });
  menu('config', () {
    item('get config', () async {
      var config = await db.getConfig();
      write(config);
    });
    menu('tag filter', () {
      item('get default tag filter', () async {
        var config = await db.getConfig();
        write(config);
      });
      item('set default tag filter (prompt)', () async {
        var config = await db.getConfig();
        var defaultTagFilter = config?.defaultTagFilter.v?.nonEmpty() ?? '*';
        var tagFilter = await prompt(
          'default tag filter (default: $defaultTagFilter, * for all)',
        );
        if (tagFilter.nonEmpty() == null) {
          tagFilter = defaultTagFilter;
        }
        if (tagFilter == '*') {
          tagFilter = '';
        }

        config ??= DbDtkStatusConfig();
        config.defaultTagFilter.v = TagsCondition(
          tagFilter,
        ).toText().nonEmpty();
        config = await db.setConfig(config);
        write(config);
      });
    });
    menu('timepoint', () {
      List<String>? dependenciesFromString(String deps, {String? defaultDeps}) {
        var depsOrNull = deps.trimmedNonEmpty() ?? defaultDeps;
        var dependencies = depsOrNull?.split(',').map((e) => e.trim()).toList();
        return dependencies;
      }

      String? tagFilterFromString(
        String tagFilter, {
        String? defaultTagFilter,
      }) {
        var tagFilterOrNull = tagFilter.trimmedNonEmpty() ?? defaultTagFilter;
        if (tagFilterOrNull == '*') {
          tagFilterOrNull = null;
        }
        return tagFilterOrNull;
      }

      item('add timepoint', () async {
        var config = await db.getConfig();
        var defaultTagFilter = config?.defaultTagFilter.v?.nonEmpty() ?? '*';

        var tagFilter = await prompt(
          'tag filter (default: $defaultTagFilter, * for all)',
        );
        var tagFilterOrNull = tagFilterFromString(
          tagFilter,
          defaultTagFilter: defaultTagFilter,
        );

        var deps = await prompt('deps (comma separated)');
        var dependencies = dependenciesFromString(deps);

        var timepoint = await db.createTimepoint(
          tagFilter: tagFilterOrNull,
          dependencies: dependencies,
        );
        write(timepoint);
      });
      Future<void> listTimepoints() async {
        var id = await db.getCurrentTimepointId();
        var list = await db.getTimepoints();
        for (var item in list) {
          write('${id == item.id ? '* ' : '  '}${item.id} ${item.toMap()}');
        }
      }

      item('edit timepoint', () async {
        await listTimepoints();
        var id = parseInt(await prompt('edit id'));
        if (id != null) {
          var timepoint = await db.getTimepoint(id);
          if (timepoint == null) {
            write('not found');
          } else {
            var defaultTagFilter = timepoint.tagFilter.v?.nonEmpty() ?? '*';
            var tagFilter = await prompt(
              'tag filter (default: $defaultTagFilter, * for all)',
            );
            var tagFilterOrNull = tagFilterFromString(
              tagFilter,
              defaultTagFilter: defaultTagFilter,
            );
            var deps = await prompt('deps (comma separated)');
            var dependencies = dependenciesFromString(
              deps,
              defaultDeps: timepoint.dependencies.v?.join(','),
            );
            timepoint = await dbDtkTimepointStore
                .record(id)
                .put(
                  db.db,
                  timepoint
                    ..tagFilter.v = tagFilterOrNull
                    ..dependencies.v = dependencies,
                );

            write('updated $timepoint');
          }
        }
      });

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
            write('current $timepoint');
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
      item('list tags', () async {
        var list = await dtkGitGetAllRepositories();
        var tags = <String>{};
        for (var item in list) {
          if (item.tags.v?.isNotEmpty ?? false) {
            tags.addAll(item.tags.v!);
          }
        }
        var tagList = tags.toList()..sort();
        write('tags: ${tagList.length}');
        for (var tag in tagList) {
          write(tag);
        }
      });
      item('add by unique name (prompt)', () async {
        var id = await prompt(
          'unique name (example: github.com/tekartik/app_common_utils.dart)',
        );
        if (id.nonEmpty() != null) {
          await dtkGitConfigDbAction((db) async {
            var repo = await db.getRepositoryOrNull(id);

            if (repo != null) {
              write('already exists $repo');
              write(repo);

              if (await prompt('update tags y/n') != 'y') {
                return;
              }
            }
            repo ??= DbDtkGitRepository()
              ..ref = dtkGitDbRepositoryStore.record(id);

            var tags = await prompt('tags');
            if (tags.nonEmpty() != null) {
              repo.tags.v = Tags.fromText(tags).toListOrNull();
            }

            repo = await db.setRepository(repo);
            write(repo);
          }, write: true);
        }
      });
      item('add (prompt)', () async {
        var url = await prompt('url');
        if (url.trimmedNonEmpty() != null) {
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
        if (url.trimmedNonEmpty() != null) {
          await dtkGitConfigDbAction((db) async {
            var id = dtkGitUniqueNameFromUrl(url);
            var repo = await db.deleteRepository(id);
            write(repo);
          }, write: true);
        }
      });
      item('delete by id (prompt)', () async {
        var id = await prompt('id');
        if (id.trimmedNonEmpty() != null) {
          await dtkGitConfigDbAction((db) async {
            var repo = await db.deleteRepository(id);
            write(repo);
          }, write: true);
        }
      });
      item('toggle omit by id (prompt)', () async {
        var id = await prompt('id');
        if (id.trimmedNonEmpty() != null) {
          await dtkGitConfigDbAction((db) async {
            var repo = await db.toggleOmit(id);
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
        if (exportPath.trimmedNonEmpty() != null) {
          await prefs.setString(
            dtkGitExportPathGlobalPrefsKey,
            absolute(normalize(exportPath)),
          );
        }
      });
    });
  });
}
