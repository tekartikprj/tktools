@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart' show newDatabaseFactoryMemory;
import 'package:sembast/timestamp.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_status_db.dart';
import 'package:test/test.dart';

void main() {
  test('the actions go to the current timepoint', () async {
    var db = await dtkStatusDbOpen(factory: newDatabaseFactoryMemory());
    try {
      var tp1 = await db.createTimepoint(
        now: Timestamp(1000, 0),
        tagFilter: 'main',
      );
      await db.createTimepoint(now: Timestamp(2000, 0), tagFilter: 'public');
      // dtk menu > config > timepoint > set current timepoint (prompt)
      await db.setCurrentTimepoint(tp1.id);
      expect((await db.getCurrentTimepoint())!.tagFilter.v, 'main');
      var action = await db.findOrCreateAction<DbDtkActionFindRepos>(
        actionFindRepos,
      );
      expect(action.timepoint.v, tp1.id);
    } finally {
      await db.close();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a deleted timepoint leaves no action behind', () async {
    var dir = Directory.systemTemp.createTempSync('dtk_status_db');
    var path = join(dir.path, 'status.db');
    try {
      var db = DtkStatusDb(await databaseFactoryIo.openDatabase(path));
      await db.createTimepoint(now: Timestamp(1000, 0));
      var tp2 = await db.createTimepoint(now: Timestamp(2000, 0));
      var action = await db.findOrCreateAction<DbDtkActionFindRepos>(
        actionFindRepos,
      );
      expect(action.timepoint.v, tp2.id);
      action
        ..status.v = actionResultOk
        ..repos.v = ['github.com/old/repo'];
      await action.put(db.db);
      // dtk menu > config > timepoint > delete timepoint (prompt)
      await db.deleteTimepoint(tp2.id);
      // sembast compacts on open once enough lines are obsolete, the deleted
      // key can then be given again.
      await db.db.compact();
      await db.close();

      db = DtkStatusDb(await databaseFactoryIo.openDatabase(path));
      try {
        // dtk menu > config > timepoint > add timepoint
        await db.createTimepoint(now: Timestamp(3000, 0));
        var found = await db.findOrCreateAction<DbDtkActionFindRepos>(
          actionFindRepos,
        );
        // A new timepoint starts with nothing done.
        expect(found.status.v, actionResultNone);
        expect(found.repos.v, isNull);
      } finally {
        await db.close();
      }
    } finally {
      dir.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
