import 'package:dev_build/menu/menu_io.dart';
import 'package:path/path.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_common_utils/env_utils.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_git_config_db.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_status_db.dart';
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

/// dtk menu
void dtkMenu() {
  late DtkStatusDb db;
  enter(() async {
    db = await getGlobalStatusDb();
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
      if (isDebug) {}
      item('add', () async {
        var url = await prompt('url');
        if (url != null) {
          await dtkGitConfigDbAction((db) async {}, write: true);
        }
      });
      item('list', () async {
        var list = await dtkGitGetAllRepositories();
        for (var item in list) {
          write('${item.id} ${item.toMap()}');
        }
      });
    });
    menu('once', () {
      item('get git config path', () async {
        var prefs = await openGlobalPrefsPrefs();
        write(prefs.getString(dtkGitExportPathGlobalPrefsKey));
        write(await dtkGetGitExportPath());
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
