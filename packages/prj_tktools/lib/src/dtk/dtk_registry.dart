import 'dart:io';

import 'package:path/path.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_common_utils/tags.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk.dart'
    show dtkGetGitExportPath, dtkGitUniqueNameFromUrl;
import 'package:tekartik_prj_tktools/src/dtk/dtk_git_config_db.dart'
    show DbDtkGitRepository, dtkGitConfigDbAction, dtkGitDbRepositoryStore;
import 'package:tekartik_prj_tktools/src/tkpub.dart'
    show tkPubGetConfigExportPath;
import 'package:tekartik_prj_tktools/src/tkpub_db.dart'
    show TkPubDbPackage, tkPubDbAction, tkPubPackagesStore;
import 'package:tekartik_prj_tktools/src/utils.dart' show tkPubFindGitTop;

/// A git repository of the dtk registry, resolved on this machine.
class DtkRegistryRepo {
  /// Unique id, `<host>/<owner>/<repo>` (`github.com/tekartik/cv.dart`), also
  /// its path relative to the git top.
  final String id;

  /// Git url, null when not registered.
  final String? gitUrl;

  /// Git ref, null for the default one.
  final String? gitRef;

  /// Tags (`public`, `main`, project specific), sorted.
  final List<String> tags;

  /// True when bulk actions skip it.
  final bool omit;

  /// Absolute local path, `<git top>/<id>`.
  final String path;

  /// True when [path] exists.
  final bool cloned;

  /// Names of the tkpub packages it holds, sorted.
  final List<String> packages;

  /// A git repository of the dtk registry, resolved on this machine.
  DtkRegistryRepo({
    required this.id,
    this.gitUrl,
    this.gitRef,
    this.tags = const [],
    this.omit = false,
    required this.path,
    required this.cloned,
    this.packages = const [],
  });

  /// Last segment of the id (`cv.dart`).
  String get name => url.split(id).last;

  /// Json map, null values left out.
  Map<String, Object?> toJson() => {
    'id': id,
    'gitUrl': ?gitUrl,
    'gitRef': ?gitRef,
    'tags': tags,
    'omit': omit,
    'path': path,
    'cloned': cloned,
    'packages': packages,
  };
}

/// A package of the tkpub registry, resolved on this machine.
class DtkRegistryPackage {
  /// Package name.
  final String name;

  /// Git url.
  final String? gitUrl;

  /// Path of the package in its repository, null at the root.
  final String? gitPath;

  /// Git ref, null for the default one.
  final String? gitRef;

  /// True when it is published on pub.dev.
  final bool published;

  /// Id of its repository (`github.com/tekartik/cv.dart`), null when the git
  /// url cannot be parsed.
  final String? repoId;

  /// Absolute local path, null when [repoId] is.
  final String? path;

  /// True when [path] holds a `pubspec.yaml`.
  final bool exists;

  /// A package of the tkpub registry, resolved on this machine.
  DtkRegistryPackage({
    required this.name,
    this.gitUrl,
    this.gitPath,
    this.gitRef,
    this.published = false,
    this.repoId,
    this.path,
    this.exists = false,
  });

  /// Json map, null values left out.
  Map<String, Object?> toJson() => {
    'name': name,
    'gitUrl': ?gitUrl,
    'gitPath': ?gitPath,
    'gitRef': ?gitRef,
    'published': published,
    'repo': ?repoId,
    'path': ?path,
    'exists': exists,
  };
}

/// The dtk git registry and the tkpub package registry, joined and resolved
/// against a git top (`<git top>/<host>/<owner>/<repo>`).
class DtkRegistry {
  /// Absolute git top.
  final String gitTop;

  /// Registered repositories, sorted by id.
  final List<DtkRegistryRepo> repos;

  /// Registered packages, sorted by name, empty when the tkpub registry was
  /// not loaded.
  final List<DtkRegistryPackage> packages;

  /// True when the tkpub registry was loaded.
  final bool packagesLoaded;

  /// The dtk git registry and the tkpub package registry.
  DtkRegistry({
    required String gitTop,
    required this.repos,
    this.packages = const [],
    this.packagesLoaded = false,
  }) : gitTop = normalize(absolute(gitTop));

  /// Load the registries.
  ///
  /// The export paths default to the global prefs (`tkpub init`, dtk_menu
  /// "set git config path"), [gitTop] to `TEKARTIK_GIT_TOP` or the folder
  /// holding the nearest `github.com`. The package registry is optional
  /// unless [requirePackages] is true.
  static Future<DtkRegistry> load({
    String? gitTop,
    String? gitConfigExportPath,
    String? pubConfigExportPath,
    bool requirePackages = false,
  }) async {
    var top = normalize(absolute(gitTop ?? await tkPubFindGitTop()));
    gitConfigExportPath ??= await dtkGetGitExportPath();
    if (gitConfigExportPath == null) {
      throw StateError(
        'dtk git registry not set: pass --git-config-export-path or run '
        'dtk_menu > once > set git config path',
      );
    }
    var dbRepos = await dtkGitConfigDbAction<List<DbDtkGitRepository>>(
      (db) => dtkGitDbRepositoryStore.query().getRecords(db.database),
      configExportPath: gitConfigExportPath,
    );

    pubConfigExportPath ??= await tkPubGetConfigExportPath();
    List<TkPubDbPackage>? dbPackages;
    if (pubConfigExportPath != null) {
      dbPackages = await tkPubDbAction<List<TkPubDbPackage>>(
        (db) => tkPubPackagesStore.query().getRecords(db.database),
        configExportPath: pubConfigExportPath,
      );
    } else if (requirePackages) {
      throw StateError(
        'tkpub registry not set: pass --pub-config-export-path or run '
        'tkpub init <export path>',
      );
    }
    return DtkRegistry.fromRecords(
      gitTop: top,
      repos: dbRepos,
      packages: dbPackages,
    );
  }

  /// Build from the database records, [packages] null when not loaded.
  factory DtkRegistry.fromRecords({
    required String gitTop,
    required List<DbDtkGitRepository> repos,
    List<TkPubDbPackage>? packages,
  }) {
    var top = normalize(absolute(gitTop));
    var registryPackages = <DtkRegistryPackage>[
      for (var dbPackage in packages ?? <TkPubDbPackage>[])
        _resolvePackage(top, dbPackage),
    ]..sort((a, b) => a.name.compareTo(b.name));
    var packagesByRepo = <String, List<String>>{};
    for (var package in registryPackages) {
      if (package.repoId != null) {
        (packagesByRepo[package.repoId!] ??= []).add(package.name);
      }
    }
    var registryRepos = <DtkRegistryRepo>[
      for (var dbRepo in repos)
        DtkRegistryRepo(
          id: dbRepo.id,
          gitUrl: dbRepo.gitUrl.v,
          gitRef: dbRepo.gitRef.v,
          tags: [...?dbRepo.tags.v]..sort(),
          omit: dbRepo.omit.v ?? false,
          path: _repoPath(top, dbRepo.id),
          cloned: Directory(_repoPath(top, dbRepo.id)).existsSync(),
          packages: packagesByRepo[dbRepo.id] ?? const [],
        ),
    ]..sort((a, b) => a.id.compareTo(b.id));
    return DtkRegistry(
      gitTop: top,
      repos: registryRepos,
      packages: registryPackages,
      packagesLoaded: packages != null,
    );
  }

  /// Repositories matching the tags expression [tagFilter] (`public &&
  /// !flutter`, see `TagsCondition`), all of them when null.
  List<DtkRegistryRepo> reposWithTags(String? tagFilter) {
    if (tagFilter == null) {
      return repos;
    }
    var condition = TagsCondition(tagFilter);
    return repos
        .where((repo) => condition.check(Tags.fromList(repo.tags)))
        .toList();
  }

  /// The repositories matching [query]: an id, a git url, an `owner/repo` or
  /// `repo` suffix, then the same suffix plus `.dart` (`sembast` finds
  /// `github.com/tekartik/sembast.dart`). Empty when none, several when
  /// ambiguous.
  List<DtkRegistryRepo> findRepos(String query) {
    query = query.trim();
    if (query.isEmpty) {
      return [];
    }
    String? urlId;
    if (query.contains('://') || query.startsWith('git@')) {
      try {
        urlId = dtkGitUniqueNameFromUrl(query);
      } catch (_) {}
    }
    for (var id in [query, ?urlId]) {
      var exact = repos.where((repo) => repo.id == id).toList();
      if (exact.isNotEmpty) {
        return exact;
      }
    }
    for (var suffix in ['/$query', '/$query.dart']) {
      var matches = repos.where((repo) => repo.id.endsWith(suffix)).toList();
      if (matches.isNotEmpty) {
        return matches;
      }
    }
    return [];
  }

  /// The package named [name], null when not registered.
  DtkRegistryPackage? findPackage(String name) {
    name = name.trim();
    for (var package in packages) {
      if (package.name == name) {
        return package;
      }
    }
    return null;
  }

  /// The packages of the repository [repoId].
  List<DtkRegistryPackage> packagesInRepo(String repoId) =>
      packages.where((package) => package.repoId == repoId).toList();

  /// Registered repositories not cloned here, omitted ones left out.
  List<DtkRegistryRepo> missingRepos({String? tagFilter}) => reposWithTags(
    tagFilter,
  ).where((repo) => !repo.cloned && !repo.omit).toList();

  /// Local checkouts (`<git top>/<host>/<owner>/<repo>/.git`) that are not
  /// registered, as ids, sorted.
  List<String> unregisteredCheckouts() {
    var known = repos.map((repo) => repo.id).toSet();
    var found = <String>[];
    List<Directory> subDirs(Directory dir) {
      try {
        return dir
            .listSync(followLinks: false)
            .whereType<Directory>()
            .where((sub) => !basename(sub.path).startsWith('.'))
            .toList();
      } catch (_) {
        return [];
      }
    }

    for (var host in subDirs(Directory(gitTop))) {
      // A host is a domain: github.com, gitlab.com...
      if (!basename(host.path).contains('.')) {
        continue;
      }
      for (var owner in subDirs(host)) {
        for (var repo in subDirs(owner)) {
          var id = url.joinAll(split(relative(repo.path, from: gitTop)));
          if (known.contains(id)) {
            continue;
          }
          if (FileSystemEntity.typeSync(join(repo.path, '.git')) !=
              FileSystemEntityType.notFound) {
            found.add(id);
          }
        }
      }
    }
    found.sort();
    return found;
  }
}

String _repoPath(String gitTop, String repoId) =>
    normalize(join(gitTop, joinAll(url.split(repoId))));

DtkRegistryPackage _resolvePackage(String gitTop, TkPubDbPackage dbPackage) {
  var gitUrl = dbPackage.gitUrl.v;
  var gitPath = dbPackage.gitPath.v;
  if (gitPath != null && (gitPath.isEmpty || gitPath == '.')) {
    gitPath = null;
  }
  String? repoId;
  if (gitUrl != null) {
    try {
      repoId = dtkGitUniqueNameFromUrl(gitUrl);
    } catch (_) {}
  }
  String? path;
  var exists = false;
  if (repoId != null) {
    path = normalize(
      join(_repoPath(gitTop, repoId), joinAll(url.split(gitPath ?? '.'))),
    );
    exists = File(join(path, 'pubspec.yaml')).existsSync();
  }
  return DtkRegistryPackage(
    name: dbPackage.id,
    gitUrl: gitUrl,
    gitPath: gitPath,
    gitRef: dbPackage.gitRef.v,
    published: dbPackage.published.v != null,
    repoId: repoId,
    path: path,
    exists: exists,
  );
}
