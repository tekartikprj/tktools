import 'package:sembast/sembast_memory.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_git_config_db.dart';
import 'package:test/test.dart';

Future<void> main() async {
  group('dtkgitconfig_db', () {
    test('simple', () async {
      var db =
          DtkGitConfigDb(await newDatabaseFactoryMemory().openDatabase('test'));

      var package = dtkGitDbRepositoryStore.record('repo1').cv()
        ..gitUrl.v = 'gitUri1';
      await db.setRepository(package);
      package = await db.getRepository('repo1');
      expect(package.gitUrl.v, 'gitUri1');
      await db.close();
    });
  });
}
