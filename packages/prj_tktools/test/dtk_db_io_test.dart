@TestOn('vm')
library;

import 'dart:io';

import 'package:fs_shim/utils/io/copy.dart' show deleteFile;
import 'package:fs_shim/utils/io/read_write.dart' show linesToIoString;
import 'package:path/path.dart';
import 'package:sembast/sembast.dart';
import 'package:tekartik_prj_tktools/dtk.dart';
import 'package:test/test.dart';

Future<void> main() async {
  group('dtk', () {
    test('format', () async {
      var exportPath = join('.dart_tool', 'tekartik_prj_tktools', 'test',
          'export', 'export.jsonl');
      await deleteFile(File(exportPath));
      await dtkConfigDbAction((db) async {}, exportPath: exportPath);
      expect(File(exportPath).existsSync(), isFalse);
      await dtkConfigDbAction((db) async {},
          exportPath: exportPath, write: true);
      expect(await File(exportPath).readAsString(),
          '{"sembast_export":1,"version":1}${Platform.isWindows ? '\r\n' : '\n'}');
      await dtkConfigDbAction((configDb) async {
        var db = configDb.database;
        await db.transaction((txn) async {
          await StoreRef.main().record('k2').put(txn, 'v2');
          await StoreRef.main().record('k1').put(txn, 'v1');
        });
      }, exportPath: exportPath, write: true);
      expect(
          await File(exportPath).readAsString(),
          linesToIoString([
            '{"sembast_export":1,"version":1}',
            '{"store":"_main"}',
            '["k1","v1"]',
            '["k2","v2"]'
          ]));
    });
  });
}
