@TestOn('vm')
library;

import 'package:tekartik_prj_tktools/dsenv.dart';
import 'package:test/test.dart';

Future<void> main() async {
  var name = '_PRJ_TKTOOLS_TEST_VAR';
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
