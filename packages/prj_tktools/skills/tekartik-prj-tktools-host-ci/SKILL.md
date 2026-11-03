---
name: tekartik-prj-tktools-host-ci
description: >-
  Use when running or reading the CI of local checkouts on this machine (Host
  CI) with the `dtk ci` command line or package:tekartik_prj_tktools/host_ci.dart:
  which project to run next, running it (pub upgrade, analyze, format, test
  host, test web, build web, build host, downgrade analyze, each step depending
  on the previous ones), retrying one step (--step) or from a step (--from),
  the failure reports kept until validated or green, step policies (warn with
  a severity, accept), skipped projects or platforms, the logs and the web
  report pages; HostCi, HostCiStore, HostCiRunQueue, HostCiReport.
---

# Host CI (`dtk ci`, tekartik_prj_tktools)

The CI of the local checkouts, run on this machine with `dev_build`'s
`run_ci`, one process per step, like the GitHub jobs of `tekartik/ci.dart`.
A desktop app can follow the same folder; the command line is enough to run
and read everything.

## Guidelines

- Read before running: `dtk ci --json` (status), `dtk ci next --json`,
  `dtk ci failures --json`. A run takes the machine for minutes (one run at a
  time, the others wait in the queue: `dtk ci queue`).
- Run: `dtk ci run <project>` (id, `owner/repo`, repo name or path),
  `dtk ci run` alone runs the next one, `--next <n>` the next n ones (what
  is next read again after each run, a project runs once), `--all-due` all
  the due ones. Exit
  code 1 when red. `-q` prints the summary only.
- Any repository from a link: `dtk ci add
  https://github.com/dart-lang/core/tree/main/pkgs/args` (a branch and a sub
  folder; `owner/repo` or a git url) clones it (shallow) in the Host CI
  checkouts folder, each full run starts with its `update` step (fetch,
  reset, clean; cloned again when cleared). `dtk ci checkouts` lists the
  clones (size, projects), `--clear <name>`, `--clear-all`, `--move-to
  temp|default|<dir>` (`--delete-old`).
- Retry after a fix: `dtk ci run <project> --from failed` (the failed step
  and the next ones: green, it closes the report) or `--step <step>` (that
  step only, never a verdict). Steps: `pub-get`, `pub-upgrade`, `analyze`,
  `format`, `test-host`, `test-web`, `build-web`, `build-host`, `downgrade`,
  and the groups `test`, `build`.
- Analyze a failure: `dtk ci context <project|run>` prints the whole report
  in Markdown (context, steps with their commands, failure logs, retry
  commands, last runs), `--full` for the whole log of the failed steps;
  `dtk ci log <project> --step failed` for the raw log; the run page
  `report/runs/<key>.html` (and `<key>.md`).
- A report stays open until green or `dtk ci validate <project>` (read and
  accepted: the project is then not proposed again while unchanged). Never
  validate on the user's behalf unless asked.
- Known failures: `dtk ci policy <project> <step> warn --severity low|medium|high`
  (a warning, the next steps run) or `accept`; `fail` restores the default.
  Skip a project (`dtk ci skip <project>`) or a platform
  (`--platform host|web`: its test and build steps).
- The run happens on the checkout as it is (dirty trees run, flagged): pub
  upgrade rewrites the lock files, the downgrade puts them back.
- `build host` is not a `run_ci` step: Host CI runs `flutter build <host>
  --no-pub` in each flutter package with the platform folder (`linux`,
  `macos`, `windows`) and `lib/main.dart`, all of them even after a failure;
  nothing to build is green.

## Data

`~/.config/tekartik/host_ci` (`TEKARTIK_HOST_CI_DIR`, `--dir`):

| Path | What |
| --- | --- |
| `host_ci.db` | sdb database (projects, runs, settings), opened per access under `host_ci.db.lock` |
| `logs/<host>/<owner>/<repo>/<run>.log` | the log of a run, a `=== <step> (n/N) ===` header per step, stderr lines prefixed `! ` |
| `queue/`, `run.lock`, `running.json` | one run at a time on the machine, the oldest asked first |
| `report/index.html`, `projects/`, `runs/` | the web pages |

## Examples

```dart
import 'package:tekartik_prj_tktools/host_ci.dart';

Future<void> main() async {
  var hostCi = await HostCi.open(client: 'my tool');
  try {
    var projects = await hostCi.getProjects();
    var next = projects.next;
    if (next != null) {
      var run = await hostCi.run(
        next.project.id,
        trigger: HostCiTrigger.next,
        onLines: (lines) => lines.forEach(print),
      );
      print(hostCiRunSummary(run, projectName: next.project.id));
    }
    for (var status in projects.failures) {
      print('${status.project.id}: ${hostCiStepsSummary(status.openFailure!)}');
    }
  } finally {
    await hostCi.close();
  }
}
```

Tests: `HostCi.open(dir: tmp, factory: newSdbFactoryMemory(), lock:
HostCiMemoryLock(), starter: HostCiFakeProcessStarter(...))` runs without real
processes (and without file locks, for widget tests in a fake async zone).
