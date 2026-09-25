@TestOn('vm')
library;

import 'dart:io';

import 'package:fs_shim/fs_shim.dart' show fileSystemDefault;
import 'package:path/path.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';
import 'package:tekartik_prj_tktools/dart_project_cache.dart';
import 'package:test/test.dart';

void main() {
  late Directory top;

  setUp(() {
    top = Directory.systemTemp.createTempSync('dart_project_cache_io');
  });

  tearDown(() {
    top.deleteSync(recursive: true);
  });

  String topPath() => dartProjectCanonicalPath(fileSystemDefault, top.path);

  void writeProject(String path, {bool flutter = false}) {
    File(join(top.path, path, 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        [
          'name: ${basename(path)}',
          'environment:',
          '  sdk: ^3.0.0',
          if (flutter) ...['dependencies:', '  flutter:', '    sdk: flutter'],
        ].join('\n'),
      );
  }

  group('startDartProjectScan', () {
    test('the io file system is scanned in an isolate', () async {
      writeProject('one', flutter: true);
      writeProject(join('one', 'example'));
      writeProject('two');
      // A link is not followed.
      Link(join(top.path, 'link')).createSync(join(top.path, 'two'));

      var progress = <int>[];
      var task = startDartProjectScan(
        fileSystemDefault,
        top.path,
        progressInterval: Duration.zero,
        onProgress: (found) => progress.add(found.projects.length),
      );
      expect(task.path, topPath());
      var result = await task.result;
      expect(result.cancelled, isFalse);
      expect(result.errors, isEmpty);
      expect(result.projects.map((project) => project.path), [
        join(topPath(), 'one'),
        join(topPath(), 'one', 'example'),
        join(topPath(), 'two'),
      ]);
      expect(result.projects.first.kind, DartProjectKind.flutter);
      expect(progress, [1, 2, 3]);

      // The same in this isolate.
      var local = await startDartProjectScan(
        fileSystemDefault,
        top.path,
        isolate: false,
      ).result;
      expect(
        local.projects.map((project) => project.path),
        result.projects.map((project) => project.path),
      );
    });

    test('a cancelled scan stops the isolate', () async {
      for (var i = 0; i < 50; i++) {
        writeProject(join('p$i', 'sub', 'sub'));
      }
      var task = startDartProjectScan(
        fileSystemDefault,
        top.path,
        progressInterval: Duration.zero,
        onProgress: (found) {},
      );
      task.cancel();
      var result = await task.result;
      expect(task.cancelled, isTrue);
      expect(result.cancelled, isTrue);
      expect(result.projects.length, lessThan(50));
      // Cancelling again does nothing.
      task.cancel();
    });

    test('a missing folder is reported', () async {
      var result = await startDartProjectScan(
        fileSystemDefault,
        join(top.path, 'missing'),
      ).result;
      expect(result.projects, isEmpty);
      expect(result.errors, hasLength(1));
    });
  });

  test('the cache scans the disk in an isolate', () async {
    writeProject('one');
    var cache = await DartProjectCache.open(newSdbFactoryMemory());
    addTearDown(cache.close);
    var result = await cache.refresh(top.path).done;
    expect(result.projects.map((project) => project.name), ['one']);
    expect(await cache.getProjects(top.path), hasLength(1));
  });
}
