---
name: tekartik-prj-tktools-dtk
description: >-
  Use when reading or writing the dtk multi-project configuration of
  package:tekartik_prj_tktools: dtkConfigDbAction and the JSONL-exported sembast
  config databases, dtkGitConfigDbAction / DbDtkGitRepository / tags / omit /
  dtkGitGetAllRepositories / dtkGitUniqueNameFromUrl, the shared dependency
  versions (dtk/dtk_dep.dart, DbDtkDepDependency, dtkDepConfigDbAction,
  dtkDepGetAllDependencies), dtkHostEnvVarGet/Set, the dsenv user env vars
  (dsUserEnvGetVar, dsUserEnvSetEncryptedVar, dtkHostname), openGlobalPrefsPrefs
  and the dtkMenu / DtkProject helpers.
---

# dtk: multi-project databases, host env and menus (tekartik_prj_tktools)

`dtk` is the state behind the tekartik multi-repo workflow: which git
repositories exist, the minimum version of the dependencies they share, the
per-host variables, and the interactive menu that drives them. Each database is
an in-memory sembast database imported from (and exported back to) a JSONL
file, so the state is diff-friendly and can be committed or synced.

VM only (`dart:io`, shells, prefs on disk).

## Guidelines

### Depending on the package

* Not published; depend on it with git:
  ```yaml
  dependencies:
    tekartik_prj_tktools:
      git:
        url: https://github.com/tekartikprj/tktools.git
        path: packages/prj_tktools
  ```
* Imports: `package:tekartik_prj_tktools/dtk.dart` (config db + git
  repositories + host env + `dtkMenu`),
  `package:tekartik_prj_tktools/dtk/dtk_dep.dart` (shared dependency
  versions), `package:tekartik_prj_tktools/dtk/dtk_prj.dart` (`DtkProject`),
  `package:tekartik_prj_tktools/dsenv.dart` (user env vars),
  `package:tekartik_prj_tktools/tkreg.dart` (the global prefs registry).
* One library must not import two of `dtk.dart`, `dtk/dtk_dep.dart` and
  `tkpub.dart` at once: each brings an extension on `DtkConfigDb` with a `db`
  getter and the call becomes ambiguous. Keep one database per library.

### The config database pattern

* `dtkConfigDbAction((db) async { ... }, exportPath: path, write: true)` is the
  low level entry point: it imports `exportPath` (missing file = empty
  database), runs the action, and exports it again only when `write: true`.
  `verbose: true` logs the import/export on stderr.
* `db` is a `DtkConfigDb`: `database` (the sembast `Database`), `exportPath`,
  `write`, `verbose`. Typed helpers add a `db` alias for `database`.
* The export is deterministic JSONL (`{"sembast_export":1,...}` then one line
  per record, sorted), which is why a write with no change produces no diff.
* The typed variants resolve their export path from the global prefs
  (`openGlobalPrefsPrefs()` from `tkreg.dart`) and throw `StateError` when the
  key is unset:

  | Database | Prefs key | Action | Getter |
  |---|---|---|---|
  | git repositories | `dtkGitExportPathGlobalPrefsKey` | `dtkGitConfigDbAction` | `dtkGetGitExportPath()` |
  | shared deps | `dtkDepExportPathGlobalPrefsKey` | `dtkDepConfigDbAction` | `dtkGetDepExportPath()` |
  | host env vars | `dtkHostEnvExportPathGlobalPrefsKey` | (used by `dtkHostEnvVarGet/Set`) | - |

* `dtkGitConfigDbAction` and `dtkDepConfigDbAction` take an optional
  `configExportPath:` that bypasses the prefs; use it in tests. Both cache the
  resolved path for the process, so set the prefs (or pass the path) before the
  first call.

### Git repositories

* A `DbDtkGitRepository` (`DbStringRecordBase`, id = `host/owner/repo`) holds
  `gitUrl`, `gitRef`, `tags` (`CvListField<String>`) and `omit`
  (`CvField<bool>`, true means "skip me in bulk actions").
* `setRepository(repository)` (extension `DtkGitConfigDbExt`) derives the id
  from `idOrNull` or from `dtkGitUniqueNameFromUrl(gitUrl)`, so registering a
  repository only needs its url. Other members: `getAllRepositories()`,
  `getRepository(id)` (throws), `getRepositoryOrNull(id)`,
  `deleteRepository(id)`, `toggleOmit(id)`, `initBuilders()`, `close()`.
* `dtkGitUniqueNameFromUrl` accepts both forms
  (`https://github.com/tekartik/common_utils.dart` and
  `git@github.com:tekartik/common_utils.dart`), strips a trailing `.git` and
  returns `github.com/tekartik/common_utils.dart`. The same string is
  `repository.uniqueName` (`DbDtkGitRepositoryExt`), next to `addTag(tag)` and
  `removeTag(tag)`, which keep the list sorted and return whether it changed.
* `dtkGitGetAllRepositories(tagFilter: 'public && !flutter')` opens the
  database, reads every repository and filters it with a tags expression
  (`&&`, `||`, `!`, parentheses; do not mix `&&` and `||` without
  parentheses; an empty expression matches everything).

### Shared dependency versions

* `DbDtkDepDependency` has a single `minVersion` field, the package name is the
  id. `dtkDepConfigDbAction` + `DtkDepConfigDbExt`
  (`getAllDependencies()`, `setDependency(id, dep)`, `getDependency(id)`,
  `getDependencyOrNull(id)`, `deleteDependency(id)`), or the one-liner
  `dtkDepGetAllDependencies()`.
* Use it to answer "which version of X must every project require", then feed
  the value into a pubspec rewrite.

### Host and user variables

* `dtkHostEnvVarGet(key)` / `dtkHostEnvVarSet(key, value)` store per-machine
  values in the host env database (`dtkHostEnvVarGet` throws when missing).
* `dsenv.dart` stores values in the *user environment* instead (via
  `process_run`'s user env file), plain or encrypted:
  `dsUserEnvSetVar(name, value)` (a `null` value deletes),
  `dsUserEnvSetEncryptedVar(name, value)` (generates a password and writes
  `<NAME>_ENC` + `<NAME>_ENC_PWD`), `dsUserClearVar(name)` (both forms).
* Read with `dsUserEnvGetVar(name)` (throws) or `dsUserEnvGetVarOrNull(name)`:
  they look at the plain variable **and** fall back to the encrypted one, so
  callers do not care how the value was stored. `...Sync` variants exist for
  every getter (`dsUserEnvGetVarSync`, `dsUserEnvGetEncryptedVarOrNullSync`...).
* The "encryption" only keeps the value out of plain sight in the env file: the
  password sits next to it. Never treat it as a secret store, and never commit
  either variable.
* `dtkHostname` is `DTK_HOSTNAME` from the shell environment, else
  `Platform.localHostname`: use it to key per-machine values.
* `'MY_KEY'.kvFromEnvEncrypted()` builds a `KeyValue`, and
  `keyValuesEncryptedMenu('secrets', [kv1, kv2])` adds a dev-menu section that
  prompts for and stores them (`promptToEnvEncrypted()`,
  `setToEnvEncrypted(value)`, `deleteFromEnvEncrypted()`).

### Menus and projects

* `dtkMenu(path: '.')` declares the whole interactive menu tree (git repos,
  deps, host env, projects, pub). Call it inside `mainMenuConsole` from
  `package:dev_build/menu/menu_io.dart`, as `tool/prj_tktool_menu.dart` does.
* `DtkProject(path)` (from `dtk/dtk_prj.dart`) manages pub workspace
  membership: `createEmptyProject(projectName: ...)`,
  `createWorkspaceRootProject()`, `addToWorkspace()`, `removeFromWorkspace()`.
  They rewrite `pubspec.yaml` in place (adding `resolution: workspace` and the
  relative path in the root `workspace:` list) and are guarded by a lock, so
  several projects can be added concurrently.
* Anti-patterns: mutating a database without `write: true`; keeping a
  `DtkConfigDb` after the action returned (it is closed); storing a real secret
  with `dsUserEnvSetEncryptedVar`; assuming `dtkGitGetAllRepositories` skips
  `omit` repositories (it does not, filter yourself).

## Examples

### A config database on an explicit path

```dart
import 'package:sembast/sembast.dart';
import 'package:tekartik_prj_tktools/dtk.dart';

/// Write then read a raw value, the file is JSONL.
Future<void> rawConfigDb(String exportPath) async {
  await dtkConfigDbAction((configDb) async {
    await StoreRef<String, String>.main()
        .record('k1')
        .put(configDb.database, 'v1');
  }, exportPath: exportPath, write: true);

  var value = await dtkConfigDbAction(
    (configDb) =>
        StoreRef<String, String>.main().record('k1').get(configDb.database),
    exportPath: exportPath,
  );
  print(value); // v1
}
```

### Set the export paths once (global registry)

```dart
import 'package:tekartik_prj_tktools/dtk.dart';
import 'package:tekartik_prj_tktools/tkreg.dart';

Future<void> initDtkPaths(String top) async {
  var prefs = await openGlobalPrefsPrefs();
  await prefs.setString(dtkGitExportPathGlobalPrefsKey, '$top/dtk_git.jsonl');
  await prefs.setString(dtkDepExportPathGlobalPrefsKey, '$top/dtk_dep.jsonl');
  await prefs.setString(
    dtkHostEnvExportPathGlobalPrefsKey,
    '$top/dtk_host_env.jsonl',
  );
  print(await dtkGetGitExportPath());
}
```

### Register a git repository and tag it

```dart
import 'package:tekartik_prj_tktools/dtk.dart';

Future<void> addRepository(String gitUrl) async {
  await dtkGitConfigDbAction((db) async {
    var repository =
        await db.getRepositoryOrNull(dtkGitUniqueNameFromUrl(gitUrl)) ??
        (DbDtkGitRepository()..gitUrl.v = gitUrl);
    repository.addTag('public');
    await db.setRepository(repository);
    print('${repository.uniqueName} ${repository.tags.v}');
  }, write: true);
}
```

### List repositories, filtered by tag, skipping the omitted ones

```dart
import 'package:tekartik_prj_tktools/dtk.dart';

Future<List<String>> publicRepositoryUrls() async {
  var repositories = await dtkGitGetAllRepositories(tagFilter: 'public');
  return repositories
      .where((repository) => repository.omit.v != true)
      .map((repository) => repository.gitUrl.v!)
      .toList();
}
```

### The shared minimum version of a dependency

```dart
import 'package:tekartik_prj_tktools/dtk/dtk_dep.dart';

Future<void> setMinVersion(String packageName, String minVersion) async {
  await dtkDepConfigDbAction((db) async {
    await db.setDependency(
      packageName,
      DbDtkDepDependency()..minVersion.v = minVersion,
    );
  }, write: true);

  for (var dependency in await dtkDepGetAllDependencies()) {
    print('${dependency.id}: ${dependency.minVersion.v}');
  }
}
```

### Per-host and per-user variables

```dart
import 'package:tekartik_prj_tktools/dsenv.dart';
import 'package:tekartik_prj_tktools/dtk.dart';

Future<void> variables() async {
  // Per machine, in the host env database.
  await dtkHostEnvVarSet('BUILD_DIR', '/var/tmp/build');
  print(await dtkHostEnvVarGet('BUILD_DIR'));

  // Per user, in the user environment file. Obfuscated, not secret.
  await dsUserEnvSetEncryptedVar('MY_TOKEN', 'value-from-the-user');
  print('$dtkHostname: ${await dsUserEnvGetVarOrNull('MY_TOKEN')}');
  await dsUserClearVar('MY_TOKEN');
}
```

### The interactive menu

```dart
// tool/prj_tktool_menu.dart
import 'package:dev_build/menu/menu_io.dart';
import 'package:tekartik_prj_tktools/dtk.dart';

Future<void> main(List<String> args) async {
  mainMenuConsole(args, () {
    dtkMenu();
  });
}
```

### Add a package to the surrounding pub workspace

```dart
import 'package:tekartik_prj_tktools/dtk/dtk_prj.dart';

Future<void> joinWorkspace(String packagePath) async {
  var project = DtkProject(packagePath);
  // Sets `resolution: workspace` and appends the relative path to the
  // `workspace:` list of the parent root pubspec.yaml.
  await project.addToWorkspace();
}
```

## More

The tkpub package registry is covered by
[../tekartik-prj-tktools-tkpub/SKILL.md](../tekartik-prj-tktools-tkpub/SKILL.md),
`local_workspace.json` and the file/yaml/lint helpers by
[../tekartik-prj-tktools-workspace/SKILL.md](../tekartik-prj-tktools-workspace/SKILL.md).
