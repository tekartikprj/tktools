---
name: tekartik-prj-tktools-tkpub
description: >-
  Use when managing git dependencies of tekartik projects with the tkpub
  registry of package:tekartik_prj_tktools: tkPubMain and the tkpub CLI
  (config set/get/list, add, remove, symlink, copy_files, init), tkPubDbAction,
  TkPubConfigDb, TkPubDbPackage (gitUrl/gitPath/gitRef/published),
  TkPubDepOverrides for pubspec_overrides.yaml, tkPubFindGithubTop,
  tkPubGetPackageLocalPath, tkPubGetConfigExportPath, tkPubGetPackageConfigMap,
  TkPubPackage/TkPubTopPath and the package:tekartik_prj_tktools/tkpub.dart
  import.
---

# tkpub: the local git package registry (tekartik_prj_tktools)

`tkpub` maps a package name to a git url (+ path + ref) so that dozens of
independent tekartik checkouts can be added to a `pubspec.yaml`, overridden or
symlinked without typing the git block every time. The registry is a sembast
database exported as a JSONL file; every read or write imports it, runs an
action and exports it back.

Everything here is VM only (`dart:io`, shells, symlinks).

## Guidelines

### Depending on the package

* `tekartik_prj_tktools` is not published; depend on it with git:
  ```yaml
  dependencies:
    tekartik_prj_tktools:
      git:
        url: https://github.com/tekartikprj/tktools.git
        path: packages/prj_tktools
  ```
* Single import for everything below:
  `import 'package:tekartik_prj_tktools/tkpub.dart';`. It re-exports
  `package:tekartik_app_cv_sembast/app_cv_sembast.dart` (so `CvField`,
  `Database`, `cvAddConstructors`... come for free).
* Do not import both `tkpub.dart` and `dtk.dart` in the same library: both add
  a `db` getter extension on `DtkConfigDb` and the call becomes ambiguous.
  Split into two libraries or hide one extension.

### The command line

* The package ships no `bin/` executable: wrap `tkPubMain(arguments)` in your
  own entry point (`example/tkpub.dart` in the package does exactly that) and
  run it with `dart run <that file>` or compile it.
* Subcommands of `tkpub`:

  | Command | Effect |
  |---|---|
  | `init <path>` | record the registry export path (JSONL file) |
  | `config set <pkg> --git-url <url> [--git-path <p>] [--git-ref <r>]` | register/update a package |
  | `config get <pkg>`, `config delete <pkg>`, `config list` | read/remove |
  | `config set-ref <ref>`, `config get-ref` | the default git ref of every package |
  | `config get-local-path <pkg>`, `config get-export-path` | resolved paths |
  | `add [dev:\|override:\|pubspec_overrides:]<pkg>...` | add to the current pubspec |
  | `remove <pkg>...`, `clear` | remove dependencies |
  | `list` | list the dependencies of the current package |
  | `symlink <pkg\|giturl>...` | symlink the package locally |
  | `copy_files <pkg> <file>... [--dir <dir>]` | copy files out of a package |

* `add` flags: `--dev`/`-d`, `--direct`, `--overrides`/`-o` (into
  `dependency_overrides`), `--pubspec-overrides`/`-p` (into
  `pubspec_overrides.yaml`), `--direct-and-pubspec-overrides`/`-b`,
  `--force`/`-f` (hosted version only), `--recursive`/`-r`,
  `--read-config`/`-c`. `list` takes `--dev` and `--overrides`.
  `copy_files --dir` defaults to `lib/src/imported`.
* Every subcommand accepts the global `--config-export-path <file>` to point
  at another registry (tests, a second tree).

### The registry database

* `tkPubDbAction((db) async { ... }, write: true)` opens the export file into
  an in-memory sembast database, runs the action and exports it again **only
  when `write: true`**. A read-only action must omit `write`.
* Without `configExportPath:`, the path comes from the global prefs key
  `tkPubExportPathGlobalPrefsKey`
  (`tkPubGetConfigExportPath()` returns it, `null` when unset); the action
  throws `StateError` when no path is known. Pass `configExportPath:`
  explicitly in tests.
* `TkPubConfigDb` is a typedef of `DtkConfigDb`; useful members come from
  `TkPubConfigDbExt`: `getAllPackages()`, `getPackage(id, addMissingRef: true)`
  (throws when absent), `getPackageOrNull(id)`, `setPackage(id, package)`,
  `deletePackage(id)`, `getConfig()`/`setConfig()`, `db` (the sembast
  `Database`), `initBuilders()`, `close()`.
* `tkPubGetAllPackages()` is not exported; use
  `tkPubDbAction((db) => db.getAllPackages())`.
* A registry entry is a `TkPubDbPackage` (a `DbStringRecordBase`, the package
  name is its `id`): `gitUrl`, `gitPath`, `gitRef`, `published`, all
  `CvField<String>`, read with `.v` and written with `.v =` or
  `.setValue(nullable)`. `addMissingRef: true` fills `gitRef` from the config
  default ref.
* Never do `TkPubDbPackage()..id = 'x'` on a fresh model (the record ref is
  null): pass the id to `setPackage(id, package)`.
* When you open a `DtkConfigDb` yourself (memory database in a test), call
  `db.initBuilders()` once before reading records, otherwise the cv
  constructors are missing.

### Paths in the tekartik tree

* `await tkPubFindGithubTop()` walks up from the current directory (or
  `dirPath:`) to the folder containing `github.com/tekartik`, the layout every
  tool assumes; `tkPubFindGithubTopOrNull()` returns `null` instead of
  throwing. Both are async and both fall back to the registry path and the dtk
  prefs.
* `tkPubGetPackageLocalPath(githubTop, packageName)` returns the absolute local
  checkout path of a registered package (`<githubTop>/<owner>/<repo>/<gitPath>`).
* `tkPubGetPackageConfigMap(pkgPath)` reads the resolved
  `package_config.json`, running `pub get` once if needed.

### pubspec_overrides.yaml

* `TkPubDepOverrides(rootPath: '.')` reads and writes the
  `dependency_overrides` map of `pubspec_overrides.yaml`:
  `exists`, `readOverrides()`, `writeOverrides(map)` (an empty map deletes the
  file, keys are sorted), `disable()` and `disabledExists`.
* `disable()` renames `pubspec_overrides.yaml` to
  `.local_pubspec_overrides.yaml` instead of deleting it, so a `pub get`
  resolves against the real dependencies while the overrides survive. There is
  no `enable()`: rename the file back yourself when you need it.

### Package helpers

* `TkPubPackage` is an alias of `dev_build`'s `PubIoPackage`: `TkPubPackage('.')`,
  `await package.ready` (fills `pubspecYaml`, `isFlutter`), then `shell`,
  `dof` (`dart` or `flutter`), `analyze()`, `hasDependency(name)`,
  `hasBuildRunnerDependency()`, `addDevDependency(name)`,
  `tryBuildRunnerBuild()` / `tryBuildRunnerWatch()` (both prompt to add
  `build_runner` when missing) and `promptBool(message)`.
* `TkPubTopPath(path: '.').recursiveBuildRunnerActions(action)` runs an action
  on every sub-package that depends on `build_runner`, grouping the output
  lines unless `noLinesGrouper: true`.
* Anti-patterns: calling `tkPubDbAction` inside another `tkPubDbAction`
  (the export file is rewritten twice), forgetting `write: true` on a mutation
  (silently lost), and hand-editing the exported JSONL instead of going through
  the CLI or the API.

## Examples

### The tkpub entry point

```dart
// tool/tkpub.dart - run with `dart run tool/tkpub.dart config list`
import 'package:tekartik_prj_tktools/tkpub.dart';

Future<void> main(List<String> arguments) async {
  await tkPubMain(arguments);
}
```

```bash
dart run tool/tkpub.dart init .local/tkpub/packages.jsonl
dart run tool/tkpub.dart config set tekartik_common_utils \
  --git-url https://github.com/tekartik/common_utils.dart
dart run tool/tkpub.dart add tekartik_common_utils
dart run tool/tkpub.dart add -p tekartik_common_utils   # pubspec_overrides.yaml
```

### Register a package and read it back

```dart
import 'package:tekartik_prj_tktools/tkpub.dart';

Future<void> registerAppDock() async {
  await tkPubDbAction((db) async {
    var package = TkPubDbPackage()
      ..gitUrl.v = 'https://github.com/tekartik/app_common_utils.dart'
      ..gitPath.v = 'app_dock';
    await db.setPackage('tekartik_app_dock', package);
  }, write: true);

  // Read only: no write flag, the export file is left untouched.
  var package = await tkPubDbAction(
    (db) => db.getPackage('tekartik_app_dock', addMissingRef: true),
  );
  print('${package.packageName} ${package.gitUrl.v} ${package.gitRef.v}');
}
```

### List the registry (explicit export path, no global prefs)

```dart
import 'package:tekartik_prj_tktools/tkpub.dart';

Future<void> dumpRegistry(String exportPath) async {
  var packages = await tkPubDbAction(
    (db) => db.getAllPackages(),
    configExportPath: exportPath,
  );
  for (var package in packages) {
    var gitPath = package.gitPath.v;
    print('${package.id}: ${package.gitUrl.v}${gitPath == null ? '' : ' ($gitPath)'}');
  }
}
```

### Resolve the local checkout of a registered package

```dart
import 'package:tekartik_prj_tktools/tkpub.dart';

Future<String> localPathOf(String packageName) async {
  var githubTop = await tkPubFindGithubTop();
  return await tkPubGetPackageLocalPath(githubTop, packageName);
}
```

### Toggle pubspec_overrides.yaml around a pub get

```dart
import 'package:tekartik_prj_tktools/tkpub.dart';

Future<void> addOverride(String rootPath) async {
  var overrides = TkPubDepOverrides(rootPath: rootPath);
  var map = await overrides.readOverrides();
  map['tekartik_common_utils'] = {'path': '../common_utils.dart'};
  await overrides.writeOverrides(map);

  // Temporarily resolve against the real dependencies:
  // renames pubspec_overrides.yaml to .local_pubspec_overrides.yaml
  await overrides.disable(verbose: true);
  print('disabled: ${overrides.disabledExists}');
}
```

### Run build_runner on every package of a tree

```dart
import 'package:tekartik_prj_tktools/tkpub.dart';

Future<void> buildAll(String top) async {
  await TkPubTopPath(path: top).recursiveBuildRunnerActions((path) async {
    var package = TkPubPackage(path);
    await package.ready;
    await package.tryBuildRunnerBuild(deleteConflictingOutput: true);
  });
}
```

## More

The dtk databases (git repositories, shared dependency versions, host env
vars) are covered by [../tekartik-prj-tktools-dtk/SKILL.md](../tekartik-prj-tktools-dtk/SKILL.md);
`local_workspace.json`, pubspec/yaml rewriting and the lint rule tools by
[../tekartik-prj-tktools-workspace/SKILL.md](../tekartik-prj-tktools-workspace/SKILL.md).
