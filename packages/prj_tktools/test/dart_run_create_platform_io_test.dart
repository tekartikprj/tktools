@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart';
import 'package:process_run/shell.dart' show whichSync;
import 'package:tekartik_prj_tktools/dart_run.dart';
import 'package:test/test.dart';

void main() {
  test(
    'flutterCreatePlatforms keeps the existing .metadata',
    () async {
      var top = Directory.systemTemp.createTempSync('dart_run_create');
      try {
        var project = join(top.path, 'my_folder');
        void write(String path, String content) => File(join(project, path))
          ..createSync(recursive: true)
          ..writeAsStringSync(content);
        write('pubspec.yaml', '''
name: fc_app
environment:
  sdk: ^3.9.0
dependencies:
  flutter:
    sdk: flutter
''');
        write(
          'lib/main_x.dart',
          "import 'package:flutter/widgets.dart';\n"
              'void main() => runApp(const SizedBox());\n',
        );
        // Tracked in git, flutter create rewrites it (revision, migration).
        var metadata = '''
# This file tracks properties of this Flutter project.
version:
  revision: "abc"
  channel: "stable"

project_type: app
''';
        write('.metadata', metadata);
        expect(await flutterCreatePlatforms(project, ['linux']), ['linux']);
        expect(Directory(join(project, 'linux')).existsSync(), isTrue);
        expect(File(join(project, '.metadata')).readAsStringSync(), metadata);
      } finally {
        top.deleteSync(recursive: true);
      }
    },
    skip: whichSync('flutter') == null ? 'flutter not found' : null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
