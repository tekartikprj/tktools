import 'package:sembast/sembast_memory.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub_package_info.dart';
import 'package:tekartik_prj_tktools/src/tkpub_db.dart';
import 'package:test/test.dart';

void main() {
  test('TkpubPackageInfo', () {
    expect(
      TkPubPackageInfo.parse('dev:test:{"dummy":"test"}'),
      TkPubPackageInfo(
        target: TkPubTarget.dev,
        name: 'test',
        def: {'dummy': 'test'},
      ),
    );
    expect(TkPubPackageInfo.parse('test'), TkPubPackageInfo(name: 'test'));
    expect(TkPubPackageInfo.parse("'test'"), TkPubPackageInfo(name: 'test'));
    expect(
      TkPubPackageInfo.parse('dev:test'),
      TkPubPackageInfo(target: TkPubTarget.dev, name: 'test'),
    );
  });
  group('tkpub_db', () {
    test('simple', () async {
      var db = TkPubConfigDb(
        database: await newDatabaseFactoryMemory().openDatabase('test'),
      );
      db.initBuilders();
      var package =
          tkPubPackagesStore.record('pkg1').cv()..gitUrl.v = 'gitUri1';
      var config = tkPubConfigRefRecord.cv()..gitRef.v = 'gitRef1';

      await config.put(db.db);
      await db.setPackage(package.id, package);
      package = await db.getPackage('pkg1');
      expect(package.gitRef.v, isNull);
      package = await db.getPackage('pkg1', addMissingRef: true);
      expect(package.gitRef.v, 'gitRef1');
      await db.close();
    });
  });
}
