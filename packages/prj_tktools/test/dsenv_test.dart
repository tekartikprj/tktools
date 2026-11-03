@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart';
import 'package:process_run/shell.dart';
import 'package:tekartik_prj_tktools/dsenv.dart';
import 'package:test/test.dart';

Future<void> main() async {
  var name = '_PRJ_TKTOOLS_TEST_VAR';
  late Directory tempDir;
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('prj_tktools_dsenv_');
    // Never the real user env file (~/.config/tekartik/process_run/env.yaml)
    var userEnvFile = File(join(tempDir.path, 'env.yaml'));
    await userEnvFile.writeAsString('');
    platformEnvironment = {
      ...platformEnvironment,
      'TEKARTIK_PROCESS_RUN_USER_ENV_FILE_PATH': userEnvFile.path,
    }..removeWhere((key, _) => key.startsWith(name));
  });
  tearDownAll(() async {
    platformEnvironment = null;
    await tempDir.delete(recursive: true);
  });
  group('dsenv', () {
    test('var', () async {
      await dsUserClearVar(name);
      expect(await dsUserEnvGetVarOrNull(name), isNull);
      expect(await dsUserEnvGetEncryptedVarOrNull(name), isNull);
      await dsUserEnvSetVar(name, 'value');
      expect(await dsUserEnvGetEncryptedVarOrNull(name), isNull);
      expect(await dsUserEnvGetVarOrNull(name), 'value');
      await dsUserClearVar(name);
      await dsUserEnvSetEncryptedVar(name, 'value 2');
      expect(await dsUserEnvGetEncryptedVarOrNull(name), 'value 2');
      expect(await dsUserEnvGetVarOrNull(name), 'value 2');
    });
  });
}
