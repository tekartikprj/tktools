import 'dart:async';

import 'package:fs_shim/fs_memory.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';
import 'package:tekartik_prj_tktools/dart_project_cache.dart';
import 'package:test/test.dart';

/// A project at [path] (`/` separated, relative to the root).
Future<void> writeProject(
  FileSystem fs,
  String path, {
  String? name,
  bool flutter = false,
  List<String>? workspace,
  bool inWorkspace = false,
  String sdk = '^3.0.0',
}) async {
  var dir = fs.directory(fs.path.join('/', path));
  await dir.create(recursive: true);
  await fs
      .file(fs.path.join(dir.path, 'pubspec.yaml'))
      .writeAsString(
        [
          'name: ${name ?? fs.path.basename(path)}',
          'environment:',
          '  sdk: $sdk',
          if (inWorkspace) 'resolution: workspace',
          if (workspace != null) ...[
            'workspace:',
            for (var package in workspace) '  - $package',
          ],
          if (flutter) ...['dependencies:', '  flutter:', '    sdk: flutter'],
        ].join('\n'),
      );
}

List<String> paths(Iterable<DartProjectInfo> projects) =>
    projects.map((project) => project.path).toList();

List<String> folderPaths(Iterable<DartProjectFolderInfo> folders) =>
    folders.map((folder) => folder.path).toList();

List<String> names(Iterable<DartProjectInfo> projects) =>
    projects.map((project) => project.name).toList();

DartProjectInfo project(String path, {String? name}) => DartProjectInfo(
  path: path,
  name: name ?? path.split('/').last,
  kind: DartProjectKind.dart,
  refreshed: DateTime(2026),
);

void main() {
  late FileSystem fs;

  setUp(() {
    fs = newFileSystemMemory();
  });

  group('DartProjectScanner', () {
    test(
      'finds the projects, their kind, not in the ignored folders',
      () async {
        await writeProject(fs, 'git/app', flutter: true);
        await writeProject(fs, 'git/lib', name: 'my_lib');
        // A test fixture of a project, a build output, hidden and dependency
        // folders are never scanned.
        await writeProject(fs, 'git/lib/test/fixture');
        await writeProject(fs, 'git/lib/build/out');
        await writeProject(fs, 'git/.hidden/project');
        await writeProject(fs, 'git/web/node_modules/project');
        // An old sdk, like `iteratePubPath`.
        await writeProject(fs, 'git/old', sdk: "'>=2.0.0 <3.0.0'");
        // Workspaces: a flutter package makes a flutter workspace.
        await writeProject(fs, 'git/ws_dart', name: '_', workspace: ['pkg']);
        await writeProject(fs, 'git/ws_dart/pkg', inWorkspace: true);
        await writeProject(
          fs,
          'git/ws_flutter',
          workspace: ['packages/app', 'packages/lib'],
        );
        await writeProject(
          fs,
          'git/ws_flutter/packages/lib',
          inWorkspace: true,
        );
        await writeProject(
          fs,
          'git/ws_flutter/packages/app',
          inWorkspace: true,
          flutter: true,
        );

        var progress = <int>[];
        var result = await DartProjectScanner(
          fs,
          '/git',
          onProgress: (found) => progress.add(found.projects.length),
        ).scan();
        expect(result.path, '/git');
        expect(result.cancelled, isFalse);
        expect(result.errors, isEmpty);
        expect(paths(result.projects), [
          '/git/app',
          '/git/lib',
          '/git/ws_dart',
          '/git/ws_dart/pkg',
          '/git/ws_flutter',
          '/git/ws_flutter/packages/app',
          '/git/ws_flutter/packages/lib',
        ]);
        expect(names(result.projects), [
          'app',
          'my_lib',
          '_',
          'pkg',
          'ws_flutter',
          'app',
          'lib',
        ]);
        expect(result.projects.map((project) => project.kind), [
          DartProjectKind.flutter,
          DartProjectKind.dart,
          DartProjectKind.dartWorkspace,
          DartProjectKind.dart,
          DartProjectKind.flutterWorkspace,
          DartProjectKind.flutter,
          DartProjectKind.dart,
        ]);
        // Reported as they are found.
        expect(progress, [1, 2, 3, 4, 5, 6, 7]);
        expect(
          result.projects.every(
            (project) => project.refreshed == result.refreshed,
          ),
          isTrue,
        );
      },
    );

    test('the progress is reported at most once per interval', () async {
      await writeProject(fs, 'git/one');
      await writeProject(fs, 'git/two');
      var progress = <int>[];
      var result = await DartProjectScanner(
        fs,
        '/git',
        progressInterval: const Duration(hours: 1),
        onProgress: (found) => progress.add(found.projects.length),
      ).scan();
      expect(progress, [1]);
      expect(result.projects, hasLength(2));
    });

    test('a missing folder is reported', () async {
      var result = await DartProjectScanner(fs, '/missing').scan();
      expect(result.projects, isEmpty);
      expect(result.errors, hasLength(1));
    });

    test('a cancelled scan stops', () async {
      await writeProject(fs, 'git/one');
      await writeProject(fs, 'git/two');
      late DartProjectScanner scanner;
      scanner = DartProjectScanner(
        fs,
        '/git',
        onProgress: (found) => scanner.cancel(),
      );
      var result = await scanner.scan();
      expect(result.cancelled, isTrue);
      expect(names(result.projects), ['one']);
    });
  });

  group('DartProjectCache', () {
    late DartProjectCache cache;

    setUp(() async {
      cache = await DartProjectCache.open(newSdbFactoryMemory(), fs: fs);
    });

    tearDown(() async {
      await cache.close();
    });

    test('empty', () async {
      expect(await cache.getFolders(), isEmpty);
      expect(await cache.getProjects(), isEmpty);
      expect(await cache.getIndexedFolder('/git'), isNull);
    });

    test('a folder is scanned once, then read from the cache', () async {
      await writeProject(fs, 'git/one');
      await writeProject(fs, 'git/one/example');
      await writeProject(fs, 'git/one-two');

      var refresh = (await cache.indexIfNeeded('/git'))!;
      expect(refresh.path, '/git');
      expect(cache.refreshes, [refresh]);
      var result = await refresh.done;
      // Sorted by path, `-` is before `/`.
      expect(names(result.projects), ['one', 'one-two', 'example']);
      expect(refresh.isDone, isTrue);
      expect(cache.refreshes, isEmpty);

      // In the cache now, a sub folder too: nothing to scan.
      expect(await cache.indexIfNeeded('/git'), isNull);
      expect(await cache.indexIfNeeded('/git/one'), isNull);
      var folder = (await cache.getIndexedFolder('/git/one/example'))!;
      expect(folder.path, '/git');
      expect(folder.refreshed, result.refreshed);
      expect(folderPaths(await cache.getTopFolders()), ['/git']);

      // A new project is only seen once refreshed.
      await writeProject(fs, 'git/one/other');
      expect(paths(await cache.getProjects('/git/one')), [
        '/git/one',
        '/git/one/example',
      ]);
      expect(paths(await cache.getProjects('/git/one/example')), [
        '/git/one/example',
      ]);
      expect(await cache.getProjects('/git/none'), isEmpty);
      expect((await cache.getProject('/git/one/'))!.name, 'one');
      expect(await cache.getProject('/git/one/other'), isNull);
    });

    test('refreshing a sub folder only replaces it', () async {
      await writeProject(fs, 'git/one');
      await writeProject(fs, 'git/one/example');
      await writeProject(fs, 'git/two');
      await (await cache.indexIfNeeded('/git'))!.done;

      await fs.directory('/git/one/example').delete(recursive: true);
      await writeProject(fs, 'git/one/other');
      await fs.directory('/git/two').delete(recursive: true);
      var changes = <String>[];
      var subscription = cache.onChanged.listen(changes.add);
      await cache.refresh('/git/one').done;
      // The folder saved is notified.
      await Future<void>.delayed(Duration.zero);
      expect(changes, ['/git/one']);
      await subscription.cancel();

      // `two` is still there: only `one` was scanned again.
      expect(paths(await cache.getProjects()), [
        '/git/one',
        '/git/one/other',
        '/git/two',
      ]);
      expect(folderPaths(await cache.getFolders()), ['/git', '/git/one']);
      expect(folderPaths(await cache.getTopFolders()), ['/git']);
      expect(
        (await cache.getIndexedFolder('/git/one/other'))!.path,
        '/git/one',
      );
      expect((await cache.getIndexedFolder('/git/two'))!.path, '/git');

      // Refreshing the top folder replaces the sub folder.
      await cache.refresh('/git').done;
      expect(paths(await cache.getProjects()), ['/git/one', '/git/one/other']);
      expect(folderPaths(await cache.getFolders()), ['/git']);
    });

    test('a running refresh is joined', () async {
      await writeProject(fs, 'git/one');
      var refresh = cache.refresh('/git');
      expect(cache.refresh('/git/'), same(refresh));
      // Below a running refresh too.
      expect(cache.refresh('/git/one'), same(refresh));
      expect(await cache.indexIfNeeded('/git/one'), same(refresh));
      await refresh.done;
      expect(cache.refresh('/git'), isNot(same(refresh)));
    });

    test('a cancelled refresh is not saved', () async {
      await writeProject(fs, 'git/one');
      var refresh = cache.refresh('/git')..cancel();
      var result = await refresh.done;
      expect(result.cancelled, isTrue);
      expect(refresh.cancelled, isTrue);
      expect(await cache.getFolders(), isEmpty);
      expect(await cache.getProjects(), isEmpty);
    });

    test('the refresh progress is notified', () async {
      await writeProject(fs, 'git/one');
      await writeProject(fs, 'git/two');
      // Every project found is notified.
      await cache.close();
      cache = await DartProjectCache.open(
        newSdbFactoryMemory(),
        fs: fs,
        progressInterval: Duration.zero,
      );
      var events = <(int, bool)>[];
      var subscription = cache.onRefresh.listen(
        (refresh) =>
            events.add((refresh.found.projects.length, refresh.isDone)),
      );
      await cache.refresh('/git').done;
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      // Started, 2 projects found, done: the listener reads the refresh when
      // notified, it only grows.
      expect(events, hasLength(4));
      expect(events.last, (2, true));
      expect(events.map((event) => event.$1).toList()..sort(), [
        for (var event in events) event.$1,
      ]);
    });

    test('several top folders', () async {
      await writeProject(fs, 'git/one');
      await writeProject(fs, 'other/two');
      await cache.refresh('/other').done;
      await cache.refresh('/git').done;
      expect(folderPaths(await cache.getTopFolders()), ['/git', '/other']);
      expect(names(await cache.getProjects()), ['one', 'two']);

      // Scanning a folder holding them replaces them.
      await cache.refresh('/').done;
      expect(folderPaths(await cache.getTopFolders()), ['/']);
      expect(names(await cache.getProjects()), ['one', 'two']);

      await cache.delete('/git');
      expect(names(await cache.getProjects()), ['two']);
      expect(folderPaths(await cache.getFolders()), ['/']);
      await cache.delete('/');
      expect(await cache.getProjects(), isEmpty);
      expect(await cache.getFolders(), isEmpty);
    });

    test('search', () async {
      await writeProject(fs, 'git/app/sqflite');
      await writeProject(fs, 'git/app/sqflite_common');
      await writeProject(fs, 'git/lib/sqflite');
      await writeProject(fs, 'git/lib/other', name: 'Sqflîte_other');
      await cache.refresh('/git').done;
      expect(paths(await cache.search('SQFLITE', from: '/git/app')), [
        '/git/app/sqflite',
        '/git/app/sqflite_common',
        '/git/lib/sqflite',
        '/git/lib/other',
      ]);
      expect(paths(await cache.search('sqflite', from: '/git/lib', limit: 2)), [
        '/git/lib/sqflite',
        '/git/lib/other',
      ]);
    });
  });

  group('searchDartProjects', () {
    var projects = [
      project('/git/github.com/tekartik/sqflite/sqflite'),
      project('/git/github.com/tekartik/sqflite/sqflite_common'),
      project('/git/github.com/tekartik/sqflite/example', name: 'sqflite_ex'),
      project('/git/github.com/tekartik/app/app_sqflite'),
      project('/git/github.com/tekartik/app/app_common'),
      project('/git/github.com/other/sqflite'),
      project('/git/github.com/other/Élio', name: 'élio'),
    ];

    List<String> search(String query, {String? from, int? limit}) =>
        paths(searchDartProjects(projects, query, from: from, limit: limit));

    test('lower case, no diacritics', () {
      expect(search('ELIO'), ['/git/github.com/other/Élio']);
      expect(search('élio'), ['/git/github.com/other/Élio']);
      expect(search('none'), isEmpty);
    });

    test('the closest to the folder first', () {
      // From the app folder: its projects first, then up to the top.
      expect(search('sqflite', from: '/git/github.com/tekartik/app'), [
        '/git/github.com/tekartik/app/app_sqflite',
        '/git/github.com/tekartik/sqflite/sqflite',
        // Starting with sqflite, the shortest name first.
        '/git/github.com/tekartik/sqflite/example',
        '/git/github.com/tekartik/sqflite/sqflite_common',
        '/git/github.com/other/sqflite',
      ]);
      // From the other folder.
      expect(search('sqflite', from: '/git/github.com/other', limit: 2), [
        '/git/github.com/other/sqflite',
        '/git/github.com/tekartik/sqflite/sqflite',
      ]);
      // From a project folder, the project itself first.
      expect(
        search('sqflite', from: '/git/github.com/other/sqflite/lib', limit: 1),
        ['/git/github.com/other/sqflite'],
      );
    });

    test('exact, then start, then word, then anywhere', () {
      expect(search('common'), [
        '/git/github.com/tekartik/app/app_common',
        '/git/github.com/tekartik/sqflite/sqflite_common',
      ]);
      expect(search('sqflite', limit: 3), [
        '/git/github.com/other/sqflite',
        '/git/github.com/tekartik/sqflite/sqflite',
        // Starting with sqflite, the shortest name first.
        '/git/github.com/tekartik/sqflite/example',
      ]);
    });

    test('every word must match, the path matches last', () {
      expect(search('app common'), ['/git/github.com/tekartik/app/app_common']);
      // `other` is only in the path.
      expect(search('other'), [
        '/git/github.com/other/Élio',
        '/git/github.com/other/sqflite',
      ]);
      expect(search('tekartik sqflite', limit: 1), [
        '/git/github.com/tekartik/sqflite/sqflite',
      ]);
      expect(search('tekartik/app'), [
        '/git/github.com/tekartik/app/app_common',
        '/git/github.com/tekartik/app/app_sqflite',
      ]);
    });

    test('no query, everything by path, the closest first', () {
      expect(search(' '), hasLength(projects.length));
      expect(search('', from: '/git/github.com/other'), [
        '/git/github.com/other/sqflite',
        '/git/github.com/other/Élio',
        '/git/github.com/tekartik/app/app_common',
        '/git/github.com/tekartik/app/app_sqflite',
        '/git/github.com/tekartik/sqflite/example',
        '/git/github.com/tekartik/sqflite/sqflite',
        '/git/github.com/tekartik/sqflite/sqflite_common',
      ]);
    });
  });
}
