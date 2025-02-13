import 'package:dev_build/menu/menu_io.dart';

import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_dep_config_db.dart';

Future<void> main(List<String> args) async {
  mainMenuConsole(args, dtkDepMenu);
}

/// Dep menu
void dtkDepMenu() {
  menu('config', () {
    menu('gitRef', () {
      item('get', () async {
        await dtkDepConfigDbAction((db) async {
          var config = await db.getConfig();
          write(config);
        }, verbose: true);
      });
      item('set ref (prompt)', () async {
        var config =
            await dtkDepConfigDbAction((db) async {
              return await db.getConfig();
            }) ??
            DbDtkDepConfigRef();
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
    menu('dependency', () {
      item('list', () async {
        await dtkDepConfigDbAction((db) async {
          var dependencies = await db.getAllDependencies();
          dependencies.sort((a, b) => a.id.compareTo(b.id));
          for (var dependency in dependencies) {
            write('${dependency.id} ${dependency.toMap()}');
          }
        });
      });
      item('delete', () async {
        var id = await prompt('dependency to delete');
        if (id.isNotEmpty) {
          await dtkDepConfigDbAction(
            (db) async {
              var deleted = await db.deleteDependency(id);
              if (deleted) {
                write('deleted');
              } else {
                write('not found');
              }
            },
            write: true,
            verbose: true,
          );
        }
      });

      item('add', () async {
        var id = await prompt('dependency to add/modify');
        if (id.isNotEmpty) {
          var dependency = await dtkDepConfigDbAction((db) async {
            return await db.getDependencyOrNull(id);
          });

          write('$id: $dependency');
          dependency ??= DbDtkDepDependency();
          var minVersion = await prompt(
            'minVersion${dependency.minVersion.isNotNull ? ' (default: ${dependency.minVersion.v})' : ''}',
          );
          if (minVersion.isNotEmpty) {
            var newDependency = await dtkDepConfigDbAction(
              (db) async {
                dependency!.minVersion.v = minVersion;
                return await db.setDependency(id, dependency);
              },
              write: true,
              verbose: true,
            );
            write(newDependency);
          }
        }

        //  'test': Version(1, 24, 0),
        //       'lints': Version(5, 0, 0),
        //       'build_runner': Version(2, 4, 13),
        //       'build_web_compilers': Version(4, 0, 11),
      });
    });
  });
}
