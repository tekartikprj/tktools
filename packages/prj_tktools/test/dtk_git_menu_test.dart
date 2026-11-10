import 'dart:async';
import 'dart:math';

import 'package:sembast/sembast_memory.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_git_menu.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_status_db.dart';
import 'package:test/test.dart';

/// A status db whose project actions wait for [release], counting the ones
/// running at the same time; they are then done already (nothing is run).
class _BlockingStatusDb extends DtkStatusDb {
  _BlockingStatusDb(super.db);

  final release = Completer<void>();
  var running = 0;
  var maxRunning = 0;

  @override
  Future<T> findOrCreateAction<T extends DbDtkAction>(
    String action, {
    Filter? filter,
    T? model,
  }) async {
    if (action != actionAnalyze || model == null) {
      return super.findOrCreateAction<T>(action, filter: filter, model: model);
    }
    running++;
    maxRunning = max(maxRunning, running);
    await release.future;
    running--;
    return (await super.findOrCreateAction<T>(
      action,
      filter: filter,
      model: model,
    ))..status.v = actionResultOk;
  }
}

void main() {
  test('the project actions run with the execution concurrency', () async {
    var db = _BlockingStatusDb(
      await newDatabaseFactoryMemory().openDatabase('status.db'),
    );
    try {
      // dtk menu > config > execution > set concurrency (prompt)
      await dbDtkExecutionConfigRecord.put(
        db.db,
        DbDtkExecutionConfig()..concurrency.v = 1,
      );
      // findRepos and findDartProject done: 3 projects in 1 repository.
      var findRepos = await db.findOrCreateAction<DbDtkActionFindRepos>(
        actionFindRepos,
      );
      await (findRepos
            ..gitTop.v = '/none'
            ..repos.v = ['repo']
            ..status.v = actionResultOk)
          .put(db.db);
      var findProjects = await db
          .findOrCreateAction<DbDtkActionFindDartProject>(
            actionFindDartProjects,
          );
      await (findProjects..status.v = actionResultOk).put(db.db);
      var repoProjects = await db
          .findOrCreateAction<DbDtkActionFindDartProject>(
            actionFindDartProjects,
            model: DbDtkActionFindDartProject()..repo.v = 'repo',
          );
      await (repoProjects
            ..dartProjects.v = ['a', 'b', 'c']
            ..status.v = actionResultOk)
          .put(db.db);

      var done = DtkDartProjectActionRunner(
        db,
        action: actionAnalyze,
      ).run(noReport: true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(db.maxRunning, 1);
      db.release.complete();
      await done;
      expect(db.maxRunning, 1);
    } finally {
      if (!db.release.isCompleted) {
        db.release.complete();
      }
      await db.close();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
