@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart';
import 'package:process_run/shell.dart' show whichSync;
import 'package:tekartik_prj_tktools/dart_run.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a linked test folder',
    () async {
      var top = Directory.systemTemp.createTempSync('create_platform_link');
      try {
        var project = join(top.path, 'proj');
        var shared = join(top.path, 'shared_test');
        File(join(project, 'pubspec.yaml'))
          ..createSync(recursive: true)
          ..writeAsStringSync(
            'name: fc_app\nenvironment:\n  sdk: ^3.9.0\n'
            'dependencies:\n  flutter:\n    sdk: flutter\n',
          );
        File(join(shared, 'a_test.dart'))
          ..createSync(recursive: true)
          ..writeAsStringSync('// shared\n');
        Link(join(project, 'test')).createSync(shared);
        await flutterCreatePlatforms(project, ['linux']);
        // flutter create wrote test/widget_test.dart through the link: removed,
        // the shared folder is left as it was.
        expect(
          Directory(shared).listSync().map((entity) => basename(entity.path)),
          ['a_test.dart'],
        );
      } finally {
        top.deleteSync(recursive: true);
      }
    },
    skip: whichSync('flutter') == null ? 'flutter not found' : null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
