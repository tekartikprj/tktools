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

## Host CI (`dtk ci`)

The CI of local checkouts, run on this machine like a GitHub workflow of
`tekartik/ci.dart` but local and fast: one `run_ci` process per step (the
host build: one `flutter build` per flutter app), each step depending on the
previous ones (a failing step skips the next ones).

| Step | `run_ci` |
| --- | --- |
| pub upgrade (pub get with `--pub-get-only`) | `--pub-upgrade` |
| analyze | `--analyze --no-pub-get` |
| format | `--format --no-pub-get` |
| test host | `--vm-test --no-pub-get` (dart vm, `flutter test`) |
| test web | `--test --no-vm-test --no-pub-get` (chrome, node) |
| build web | `--build --no-pub-get` |
| build host | not `run_ci`: Host CI runs `flutter build linux` (`macos`, `windows`) `--no-pub` in each flutter app having the platform folder and `lib/main.dart` |
| pub downgrade, analyze downgrade, pub restore | `--pub-downgrade`, `--analyze` on the lowest versions, then the lock files put back and `--pub-get` |

```bash
dtk ci add [<path|owner/repo>...]       # follow checkouts (the current folder)
dtk ci                                  # status: the due ones first
dtk ci next                             # what runs next and why
dtk ci run [<project>...] [--all-due]   # the next one by default
dtk ci run --next 3                     # the next 3 ones, one after the other
dtk ci run <project> --step analyze     # retry one step (repeatable; test, build, failed)
dtk ci run <project> --from failed      # the failed step and the next ones
dtk ci failures                         # reports kept until validated or green
dtk ci validate <project>               # read and accepted
dtk ci log <project|run> [--step failed]
dtk ci context [<project|run>] [--copy] [--full]  # Markdown report for Claude
dtk ci report [--open]                  # the web pages
dtk ci skip <project> [--platform host|web]
dtk ci policy <project> build warn [--severity low|medium|high]   # or accept, fail
dtk ci steps <project> [analyze format test ...] [--pub-get-only]
dtk ci queue                            # the run in progress, the waiting ones
```

- Next: never run, then changed since the last run, then red (not
  validated), then stale green; within a bucket, the oldest started first.
- One run at a time on the machine: the runs asked by several processes
  (the command line, an app) wait in a queue, the oldest asked first.
- A failure report (red, or a warning) stays open until a green run (a full
  one, or a `--from` re-run starting at the failed step) or `validate`. A
  step policy turns its failure into a warning (with a severity) or accepts it.
- Everything is in `~/.config/tekartik/host_ci` (`TEKARTIK_HOST_CI_DIR`):
  `host_ci.db` (opened for each access, under a file lock), `logs/`, the
  queue, and `report/` (static pages: the global report, a page per project
  and per run with the log of each step, written after each run; each run
  page has its Markdown report next to it, `runs/<key>.md`).
- `dtk ci context` is the report to paste to Claude (or any LLM): the
  context (checkout, commit, tree, tools, options, open report), every
  step with its exact command, status, duration and exit code, the log of
  each failure (the failing package's part; for tests, the failing tests
  in order with their errors, a repeated error once), the retry commands
  and the last runs.
- From Dart: `HostCi.open()` in `package:tekartik_prj_tktools/host_ci.dart`.

## Doc

* [Local workspace](doc/local_workspace.md): `local_workspace.json`
  (`DtkLocalWorkspace`) format and resolution.
