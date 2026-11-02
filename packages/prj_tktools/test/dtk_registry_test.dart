@TestOn('vm')
library;

import 'package:tekartik_prj_tktools/dtk.dart';
import 'package:test/test.dart';

import 'src/dtk_test_tree.dart';

void main() {
  late DtkTestTree tree;
  late DtkRegistry registry;

  setUpAll(() async {
    tree = await DtkTestTree.create();
    registry = await DtkRegistry.load(
      gitTop: tree.gitTop,
      gitConfigExportPath: tree.gitExport,
      pubConfigExportPath: tree.pubExport,
      requirePackages: true,
    );
  });

  tearDownAll(() async {
    await tree.delete();
  });

  test('repos', () {
    expect(registry.repos.map((repo) => repo.id), [
      'github.com/fork/cv.dart',
      'github.com/tekartik/cv.dart',
      'github.com/tekartik/missing.dart',
      'github.com/tekartik/sembast.dart',
    ]);
    var cv = registry.repos[1];
    expect(cv.toJson(), {
      'id': 'github.com/tekartik/cv.dart',
      'gitUrl': 'https://github.com/tekartik/cv.dart',
      'tags': ['main', 'public'],
      'omit': false,
      'path': tree.gitTopPath('github.com/tekartik/cv.dart'),
      'cloned': true,
      'packages': ['cv'],
    });
    expect(registry.repos[0].omit, isTrue);
    expect(registry.repos[2].cloned, isFalse);
    expect(registry.repos[3].packages, ['sembast']);
  });

  test('packages', () {
    expect(registry.packagesLoaded, isTrue);
    expect(registry.packages.map((package) => package.name), [
      'bad',
      'cv',
      'sembast',
    ]);
    expect(registry.findPackage('cv')!.toJson(), {
      'name': 'cv',
      'gitUrl': 'https://github.com/tekartik/cv.dart',
      'gitPath': 'packages/cv',
      'published': true,
      'repo': 'github.com/tekartik/cv.dart',
      'path': tree.gitTopPath('github.com/tekartik/cv.dart/packages/cv'),
      'exists': true,
    });
    var sembast = registry.findPackage('sembast')!;
    expect(sembast.repoId, 'github.com/tekartik/sembast.dart');
    expect(sembast.published, isFalse);
    expect(sembast.exists, isFalse);
    var bad = registry.findPackage('bad')!;
    expect(bad.repoId, isNull);
    expect(bad.path, isNull);
    expect(registry.findPackage('none'), isNull);
    expect(
      registry
          .packagesInRepo('github.com/tekartik/cv.dart')
          .map((package) => package.name),
      ['cv'],
    );
  });

  test('findRepos', () {
    List<String> find(String query) =>
        registry.findRepos(query).map((repo) => repo.id).toList();
    expect(find('github.com/tekartik/cv.dart'), [
      'github.com/tekartik/cv.dart',
    ]);
    expect(find('https://github.com/tekartik/sembast.dart'), [
      'github.com/tekartik/sembast.dart',
    ]);
    expect(find('git@github.com:tekartik/sembast.dart.git'), [
      'github.com/tekartik/sembast.dart',
    ]);
    expect(find('tekartik/cv.dart'), ['github.com/tekartik/cv.dart']);
    expect(find('sembast'), ['github.com/tekartik/sembast.dart']);
    // Ambiguous.
    expect(find('cv.dart'), [
      'github.com/fork/cv.dart',
      'github.com/tekartik/cv.dart',
    ]);
    expect(find('none'), isEmpty);
    expect(find(''), isEmpty);
  });

  test('tags', () {
    expect(registry.reposWithTags('public && !main').map((repo) => repo.id), [
      'github.com/tekartik/sembast.dart',
    ]);
    expect(registry.reposWithTags(null), hasLength(4));
  });

  test('sync', () {
    // The omitted fork is left out.
    expect(registry.missingRepos().map((repo) => repo.id), [
      'github.com/tekartik/missing.dart',
    ]);
    expect(registry.missingRepos(tagFilter: 'public'), isEmpty);
    expect(registry.unregisteredCheckouts(), ['github.com/other/unregistered']);
  });

  test('no package registry', () async {
    var registry = await DtkRegistry.load(
      gitTop: tree.gitTop,
      gitConfigExportPath: tree.gitExport,
      // A missing export is an empty registry.
      pubConfigExportPath: '${tree.pubExport}.none',
    );
    expect(registry.packages, isEmpty);
    expect(registry.repos[1].packages, isEmpty);
  });
}
