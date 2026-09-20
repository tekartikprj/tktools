---
name: tekartik-prj-tktools-workspace
description: >-
  Use when aggregating tekartik checkouts into one IDE/agent workspace or when
  rewriting project files with package:tekartik_prj_tktools: local_workspace.json
  and DtkLocalWorkspace (links/add-git/add/add-dir), LocalWorkspaceHelper
  (loadConfig, resolve, resolveFolders, getTopFolders, setupVsCode, setupIdea,
  setupClaude, setupAgy), localWorkspaceCreateSymlink, localWorkspaceDoAdd,
  pathVersionGet/Set/Bump, the YamlEditor updateOrAdd/toLines extension,
  linesToIoText/readLines/writeLines, arbFormat/arbGenerateIntl, the tklint
  rules API (TkLintPackage, TkLintRules, tklintFixRules, tklintMain), SudoShell
  and shellArgsToCommandList.
---

# Local workspaces and project file tools (tekartik_prj_tktools)

A tekartik machine holds dozens of independent git checkouts under
`<git top>/github.com/<owner>/<repo>`. A *local workspace* is a folder with a
`local_workspace.json` that names the projects to aggregate; resolving it
creates the symlinks under `projects/` and writes the VS Code / IntelliJ /
Claude / Antigravity project files. The same package also carries the small
file tools used to maintain those projects: pubspec version, yaml rewriting,
line endings, arb files and lint rules.

VM only (`dart:io`, symlinks, shells).

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
* Imports, one library per topic:
  `package:tekartik_prj_tktools/local_workspace.dart`,
  `package:tekartik_prj_tktools/version.dart` (also re-exports
  `tekartik_common_utils/version_utils.dart`, so `Version` comes with it),
  `package:tekartik_prj_tktools/yaml_edit.dart` (also re-exports `yaml` and
  `yaml_edit`), `package:tekartik_prj_tktools/file_lines_io.dart`,
  `package:tekartik_prj_tktools/arb.dart`,
  `package:tekartik_prj_tktools/tklint.dart` +
  `package:tekartik_prj_tktools/tklint_bin.dart`,
  `package:tekartik_prj_tktools/sudo_shell.dart`,
  `package:tekartik_prj_tktools/utils/shell_utils.dart`.

### local_workspace.json

* The file (`localWorkspaceConfigFileName`) lives at the workspace root and is
  modelled by `DtkLocalWorkspace`, all fields optional:

  | Json key | Field | Content | Symlink created |
  |---|---|---|---|
  | `links` | `links` | paths relative to the workspace | `projects/<basename>` |
  | `add-git` | `addGit` | package name, git url or `owner/repo` | `projects/<owner>/<repo>` |
  | `add` | `add` | package name | `projects/<owner>/<repo>/<gitPath>` |
  | `add-dir` | `addDir` | relative or absolute folders | none |

* `add` and `add-git` resolve the package through the tkpub registry (see the
  `tekartik-prj-tktools-tkpub` skill), so a package must be registered there
  first; `links` and `add-dir` need no lookup. `add-dir` is how a project
  outside the `github.com` tree joins the workspace; a missing folder is
  skipped with a warning.
* `LocalWorkspaceHelper(path: '.')` is the entry point. It calls
  `initCvLocalWorkspace()` for you (call that function yourself only when
  decoding `DtkLocalWorkspace` without the helper). Members:
  `configFile`, `resolvedFile`, `resolvedInputFile`, `loadConfig()` (throws
  `StateError` when the json is missing), `checkConfig()`,
  `resolve(config)`, `getOrResolve(force: false)`, `getResolvedConfig()`,
  `writeResolved(resolved)`, `resolveFolders(config)` (relative, `'.'` first),
  `getTopFolders()` (absolute canonical), and the generators
  `setupVsCode(config)`, `setupIdea(config)`, `setupClaude(config)`,
  `setupAgy(config)`.
* Resolution is cached under `.local/local_workspace/`: `resolved.json`
  (`DtkResolvedLocalWorkspace`: `input`, `resolved` entries with
  `type`/`source`/`path`, and `version` =
  `dtkResolvedLocalWorkspaceVersion`) plus `resolved_input.json`, the input
  copy used by `checkConfig()` to detect a changed `local_workspace.json`.
  Unknown json keys are ignored and make the check always report a change.
* Symlinks: `localWorkspaceDoAdd(packageName, workspacePath, githubTop)` links
  the package folder inside its repo, `localWorkspaceDoAddGit(...)` links the
  whole repo, and both call `localWorkspaceCreateSymlink(absoluteLinkPath,
  localTarget)`, which deletes an existing link first. `doAdd` throws when a
  repo-level link created by `add-git` already covers the path: pick one style
  per repo. Get `githubTop` from `tkPubFindGithubTop()` (tkpub skill).
* The workspace root itself (`.`) is always the first resolved folder. Never
  commit the `projects/` symlinks or `.local/`.

### Versions, yaml and line endings

* `pathVersionGet(path: '.')` returns the `Version` of the pubspec at a path,
  `pathVersionSet(path: '.', version: v)` writes it, and
  `pathVersionBump(path: '.', patch: true | minor: true | major: true |
  ext: true)` bumps it (no flag bumps the build/pre-release part, else the
  patch). All take `path:` as a **named** argument and print what they do.
* `YamlEditor` gets `updateOrAdd(path, value)` (creates the intermediate maps
  when the path does not exist, and does nothing when both the existing and
  the new value are empty) and `toLines()`. Use it instead of `update`, which
  throws on a missing path. Editing yaml this way preserves comments and
  formatting, unlike re-emitting a parsed map.
* `file_lines_io.dart` keeps generated files with the platform line endings:
  `linesToIoText(lines)`, `textToIoText(text)`, `linesFromIoText(text)`, and
  on `File`: `readLines()` / `writeLines(lines)`. Write lines, not a string
  with hard-coded `\n`, or Windows checkouts get a whole-file diff.

### arb (Flutter l10n) files

* `arbFormat(path: '.', verbose: true)` rewrites every `.arb` file of the l10n
  directory with sorted keys (`@@locale` first, then each key followed by its
  `@key` metadata); `arbSortedKeys(keys)` exposes that ordering.
* `arbL10nDirectory(path)` returns `lib/l10n` or the `arb-dir` of `l10n.yaml`.
  `arbGenerateIntl(path: '.')` runs `flutter gen-l10n` in every package that
  has one, and `arbRecursive(path: '.', action: ...)` is the generic recursive
  walk over packages with an l10n directory.

### Lint rules (tklint)

* `TkLintPackage('.', verbose: true)` reads a package's analysis options:
  `getRules('analysis_options.yaml', handleInclude: true)` returns the
  effective `TkLintRules` (following `include:`), `fromInclude: true` returns
  only what the file adds on top of its include, `getIncludeRules(path)`
  returns the included ones, and `resolvePath('package:tekartik_lints/...')`
  resolves a `package:` include to a file path.
* `TkLintRules` holds `rules` (`List<TkLintRule>`, `name` + `enabled`) with
  `add`, `merge(other)`, `sort()`, `isEnabled(name)`, `areAllEnabled`,
  `removeRuleNames([...])`, `removeDifferentRules(fromRules)`,
  `removeObsoleteRules()`, `toStringList(forceAny: true)` and
  `toYamlObject()`. `writeRules(path, rules)` rewrites `linter: rules:` in
  place and only when the content changes.
* `tklintFixRules(dir, analysisOptionsPath: 'analysis_options.yaml',
  options: TklintFixRulesOptions(include: 'package:x/analysis_options.yaml',
  verbose: true))` is the batch form, and `tklintMain(arguments)`
  (`tklint_bin.dart`) is the CLI: `list-rules [file] [--force-any]
  [--no-include] [--from <file>] [--from-include]` and
  `fix-rules [file] [--include <file>] [--recursive]`. The package ships no
  `bin/`, wrap `tklintMain` in your own entry point as `example/tklint.dart`
  does.

### Shell helpers

* `SudoShell(password: password).run('apt update')` feeds the password to
  `sudo --stdin` (`interactive: true` forwards the real stdin instead). Read
  the password from the user or from a user env var; never hard-code it and
  never log it.
* `shellArgsToCommandList(args, separator: ';')` turns
  `results.rest` (args package) into an `Iterable<ShellCommand>`, splitting on
  a separator argument, so one option can carry several commands.

## Examples

### A local_workspace.json

```json
{
  "links": ["../../my_app"],
  "add-git": ["tekartik_common_utils", "tekartik/dev_test.dart"],
  "add": ["tekartik_lints"],
  "add-dir": ["../../elsewhere/some_project"]
}
```

### Resolve a workspace and write the editor project files

```dart
import 'package:tekartik_prj_tktools/local_workspace.dart';

Future<void> setupWorkspace(String path) async {
  var helper = LocalWorkspaceHelper(path: path);
  var config = await helper.loadConfig();

  // Relative folders, '.' included, resolved (and cached) on demand.
  for (var folder in await helper.resolveFolders(config)) {
    print(folder);
  }

  await helper.setupVsCode(config); // <dir>.code-workspace
  await helper.setupIdea(config); // .idea/modules.xml + <dir>.iml
  await helper.setupClaude(config); // .claude/settings.json
  await helper.setupAgy(config); // .gemini/antigravity-cli/settings.json
}
```

### Detect a stale resolution

```dart
import 'package:tekartik_prj_tktools/local_workspace.dart';

Future<void> ensureResolved(String path) async {
  var helper = LocalWorkspaceHelper(path: path);
  if (!await helper.checkConfig()) {
    print('${helper.configFile.path} changed, re-resolving');
    await helper.writeResolved(await helper.resolve(await helper.loadConfig()));
  }
  print(await helper.getTopFolders());
}
```

### Add a package to the workspace by hand

```dart
import 'package:tekartik_prj_tktools/local_workspace.dart';

/// [githubTop] is typically `await tkPubFindGithubTop()`.
Future<void> addPackages(String workspacePath, String githubTop) async {
  // projects/<owner>/<repo>/<gitPath> -> local package folder
  await localWorkspaceDoAdd('tekartik_lints', workspacePath, githubTop);
  // projects/<owner>/<repo> -> local repository folder
  await localWorkspaceDoAddGit('tekartik_common_utils', workspacePath, githubTop);
}
```

### Read, set and bump a package version

```dart
import 'package:tekartik_prj_tktools/version.dart';

Future<void> release(String path) async {
  var version = await pathVersionGet(path: path);
  print('current: $version');
  await pathVersionSet(path: path, version: Version(1, 2, 0));
  await pathVersionBump(path: path, patch: true); // 1.2.1
}
```

### Add a key to a pubspec.yaml without losing the comments

```dart
import 'dart:io';

import 'package:tekartik_prj_tktools/file_lines_io.dart';
import 'package:tekartik_prj_tktools/yaml_edit.dart';

Future<void> setResolutionWorkspace(File pubspecFile) async {
  var editor = YamlEditor(await pubspecFile.readAsString());
  editor.updateOrAdd(['resolution'], 'workspace');
  editor.updateOrAdd(['environment', 'sdk'], '^3.12.0');
  await pubspecFile.writeLines(editor.toLines());
}
```

### Diff the lint rules of a package against its include

```dart
import 'package:tekartik_prj_tktools/tklint.dart';

Future<void> extraRules(String path) async {
  var package = TkLintPackage(path, verbose: true);
  var rules = await package.getRules(
    'analysis_options.yaml',
    handleInclude: true,
    fromInclude: true, // only what this package adds on top of its include
  );
  for (var line in rules.toStringList(forceAny: true)) {
    print(line);
  }

  // Batch form: rewrite the file, keeping only the real differences.
  await tklintFixRules(
    path,
    options: TklintFixRulesOptions(verbose: true),
  );
}
```

### Format the arb files of a tree

```dart
import 'package:tekartik_prj_tktools/arb.dart';

Future<void> formatArb(String top) async {
  await arbFormat(path: top, verbose: true);
  await arbRecursive(
    path: top,
    action: (path) async => print('l10n in ${arbL10nDirectory(path).path}'),
  );
}
```

## More

The tkpub registry that `add`/`add-git` resolve against is covered by
[../tekartik-prj-tktools-tkpub/SKILL.md](../tekartik-prj-tktools-tkpub/SKILL.md),
and the dtk databases by
[../tekartik-prj-tktools-dtk/SKILL.md](../tekartik-prj-tktools-dtk/SKILL.md).
The `local_workspace.json` format is also documented in `doc/local_workspace.md`
of the package.
