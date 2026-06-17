import 'dart:io';
import 'package:tekartik_prj_tktools/tkpub.dart';
import 'package:test/test.dart';

void main() {
  group('TkPubDepOverrides', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'tkpub_dep_overrides_test_',
      );
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('basic read/write/disable flow', () async {
      var depOverrides = TkPubDepOverrides(rootPath: tempDir.path);

      // Initially empty
      expect(depOverrides.exists, isFalse);
      expect(depOverrides.disabledExists, isFalse);
      expect(await depOverrides.readOverrides(), isEmpty);

      // Write overrides
      var map = {
        'pkg_a': {'path': '../pkg_a'},
        'pkg_b': {'path': '../pkg_b'},
      };
      await depOverrides.writeOverrides(map);
      expect(depOverrides.exists, isTrue);

      // Read back
      var read = await depOverrides.readOverrides();
      expect(read, {
        'pkg_a': {'path': '../pkg_a'},
        'pkg_b': {'path': '../pkg_b'},
      });

      // Verify YAML formatting is standard block-style
      var yamlContent = await depOverrides.overridesFile.readAsString();
      expect(yamlContent, '''
dependency_overrides:
  pkg_a:
    path: ../pkg_a
  pkg_b:
    path: ../pkg_b
''');

      // Disable
      var disableSuccess = await depOverrides.disable();
      expect(disableSuccess, isTrue);
      expect(depOverrides.exists, isFalse);
      expect(depOverrides.disabledExists, isTrue);

      var disabledYamlContent = await depOverrides.disabledOverridesFile
          .readAsString();
      expect(disabledYamlContent, contains('pkg_a'));
    });
  });
}
