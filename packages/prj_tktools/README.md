# Tekartik prj tktools

## dtk command line

Read only queries of the dtk git registry (repositories) and the tkpub registry
(packages), resolved against the git top (`<git top>/<host>/<owner>/<repo>`),
for scripts and agents. Add `--json` for a machine readable output.

The package ships no executable: a tools package declares it, with a
`bin/dtk.dart` of one line and `dtk:` in its pubspec `executables:`.

```dart
import 'package:tekartik_prj_tktools/dtk.dart';

Future<void> main(List<String> arguments) => dtkMain(arguments);
```

```bash
dtk repos [--tag 'public && !flutter']   # registered repositories
dtk repo sembast                         # id, url, owner/repo, repo or repo minus .dart
dtk packages [--repo cv.dart] [--published]
dtk package cv
cd "$(dtk path sembast)"                 # a package, else a repository
dtk sync [--tag main] [--clone]          # missing clones, unregistered checkouts
```

The registries are private data: `dtk` reads the export paths set once in the
global prefs (`tkpub init <export>`, dtk menu "set git config path"), or the
`--git-config-export-path` / `--pub-config-export-path` options. The git top is
`--git-top`, else `TEKARTIK_GIT_TOP`, else the folder holding the nearest
`github.com`. From Dart: `DtkRegistry.load()` in `package:tekartik_prj_tktools/dtk.dart`.

## Doc

* [Local workspace](doc/local_workspace.md): `local_workspace.json`
  (`DtkLocalWorkspace`) format and resolution.
