@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart';
import 'package:sembast/sembast_memory.dart' show newDatabaseFactoryMemory;
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart' hide Finder;
import 'package:tekartik_prj_tktools/src/bin/tkfind.dart';
import 'package:tekartik_prj_tktools/src/bin/tkpub.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_config_db.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_prj.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_status_db.dart';
import 'package:tekartik_prj_tktools/src/local_workspace.dart';
import 'package:tekartik_prj_tktools/src/tkpub/tkpub_deps.dart';
import 'package:tekartik_prj_tktools/src/tkpub_db.dart';
import 'package:test/test.dart';

/// Offline regression tests, in temp folders and memory databases only.
void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tktools_regression_');
  });
  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('tkpub config set keeps the other fields', () async {
    var export = join(tmp.path, 'tkpub_export.jsonl');
    await tkPubDbAction(
      (db) async {
        await db.setPackage(
          'pkg',
          TkPubDbPackage()
            ..gitUrl.v = 'https://github.com/x/y'
            ..gitRef.v = 'dart3a'
            ..published.v = '1.2.3',
        );
      },
      write: true,
      configExportPath: export,
    );
    await TkPubCommand().parseAndRun([
      '--config-export-path=$export',
      'config',
      'set',
      'pkg',
      '--git-path',
      'sub',
    ]);
    var package = await tkPubDbAction(
      (db) => db.getPackage('pkg'),
      configExportPath: export,
    );
    expect(package.toMap(), {
      'gitUrl': 'https://github.com/x/y',
      'gitPath': 'sub',
      'gitRef': 'dart3a',
      'published': '1.2.3',
    });

    // A new package still needs its git url
    await expectLater(
      TkPubCommand().parseAndRun([
        '--config-export-path=$export',
        'config',
        'set',
        'new_pkg',
      ]),
      throwsArgumentError,
    );
  });

  test('a new timepoint keeps the default tag filter', () async {
    var db = DtkStatusDb(
      await newDatabaseFactoryMemory().openDatabase('status.db'),
    );
    await db.setConfig(DbDtkStatusConfig()..defaultTagFilter.v = 'public');
    var timepoint = await db.createTimepoint();
    var config = (await db.getConfig())!;
    expect(config.defaultTagFilter.v, 'public');
    expect(config.currentTimepoint.v, timepoint.id);
    await db.deleteTimepoint(timepoint.id);
    expect((await db.getConfig())!.defaultTagFilter.v, 'public');
    await db.close();
  });

  group('tkfind', () {
    Future<List<String>> find({
      List<String> words = const [],
      List<String> globs = const [],
      List<String> texts = const [],
      List<String> exts = const [],
    }) async {
      var finder = Finder(
        tmp.path,
        FinderOptions(
          words: words,
          fileOnly: true,
          dirOnly: false,
          showHidden: false,
          globs: globs,
          texts: texts,
          exts: exts,
        ),
      );
      return [
        await for (var entity in finder.find())
          posix.joinAll(split(finder.entityRelativePath(entity))),
      ];
    }

    setUp(() async {
      for (var path in ['README.md', 'Foo.dart', 'bar.txt', 'sub/other.dart']) {
        var file = File(join(tmp.path, path));
        await file.parent.create(recursive: true);
        await file.writeAsString('');
      }
    });

    test('words', () async {
      expect(await find(words: ['readme']), ['README.md']);
      expect(await find(words: ['zzz']), isEmpty);
    });
    test('globs', () async {
      expect(await find(globs: ['*.dart']), ['Foo.dart', 'sub/other.dart']);
      expect(await find(globs: ['sub/*.dart']), ['sub/other.dart']);
    });
    test('text and ext ignore case', () async {
      expect(await find(texts: ['README']), ['README.md']);
      expect(await find(texts: ['foo']), ['Foo.dart']);
      expect(await find(exts: ['DART']), ['Foo.dart', 'sub/other.dart']);
    });
  });

  test('setupClaude keeps an unreadable settings.json', () async {
    var main = join(tmp.path, 'main');
    await Directory(join(tmp.path, 'other')).create();
    await Directory(join(main, '.claude')).create(recursive: true);
    await File(
      join(main, 'local_workspace.json'),
    ).writeAsString('{"links": ["../other"]}');
    var settingsFile = File(join(main, '.claude', 'settings.json'));
    var content = '{\n  // a comment\n  "model": "opus"\n}\n';
    await settingsFile.writeAsString(content);
    var helper = LocalWorkspaceHelper(path: main);
    await expectLater(
      helper.setupClaude(await helper.loadConfig()),
      throwsStateError,
    );
    expect(await settingsFile.readAsString(), content);

    // A readable one keeps its other settings
    await settingsFile.writeAsString('{"model": "opus"}');
    await helper.setupClaude(await helper.loadConfig());
    var text = await settingsFile.readAsString();
    expect(text, contains('"model": "opus"'));
    expect(text, contains('additionalDirectories'));
  });

  test('an unreadable registry is never overwritten', () async {
    var exportFile = File(join(tmp.path, 'export.jsonl'));
    var content =
        '{"sembast_export":1,"version":1}\n{"store":"packages"}\n["a",{"gitUrl":"u1"}]\nnot json\n';
    await exportFile.writeAsString(content);
    await expectLater(
      dtkConfigDbAction((_) async {}, exportPath: exportFile.path, write: true),
      throwsStateError,
    );
    expect(await exportFile.readAsString(), content);
    // Read only, still a warning only
    await dtkConfigDbAction((_) async {}, exportPath: exportFile.path);
    expect(await exportFile.readAsString(), content);
  });

  test('sub projects skip an unreadable folder', () async {
    var pkg = Directory(join(tmp.path, 'a_pkg'));
    await pkg.create();
    await File(join(pkg.path, 'pubspec.yaml')).writeAsString('''
name: a_pkg
environment:
  sdk: ^3.0.0
''');
    var locked = Directory(join(tmp.path, 'locked'));
    await locked.create();
    await Process.run('chmod', ['000', locked.path]);
    try {
      expect(await DtkProject(tmp.path).getSubProjects(), [pkg.path]);
    } finally {
      await Process.run('chmod', ['755', locked.path]);
    }
  }, skip: (Platform.isWindows || _isRoot) ? 'chmod needed' : null);

  test('clear without --pubspec-overrides deletes nothing', () async {
    var overridesFile = File(join(tmp.path, 'pubspec_overrides.yaml'));
    await File(join(tmp.path, 'pubspec.yaml')).writeAsString('''
name: a_pkg
environment:
  sdk: ^3.0.0
''');
    await overridesFile.writeAsString('dependency_overrides:\n');
    await TkPubDepsManager(path: tmp.path).clear();
    expect(overridesFile.existsSync(), isTrue);
  });
}

bool get _isRoot {
  try {
    return (Process.runSync('id', ['-u']).stdout as String).trim() == '0';
  } catch (_) {
    return false;
  }
}
