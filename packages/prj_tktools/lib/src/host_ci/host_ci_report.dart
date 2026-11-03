import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tekartik_prj_tktools/src/host_ci/host_ci.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_lock.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_markdown.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_model.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_next.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_runner.dart';

/// The web report of Host CI: static pages in `<dir>/report`, opened from
/// the file system, no server.
///
/// - `index.html`: the global report: the run in progress and the queue, the
///   failure reports kept open (red and warnings, until validated or green),
///   every project with its last run, step by step.
/// - `projects/<id>.html`: the runs of a project, the latest first.
/// - `runs/<key>.html`: one run, its steps and the log of each step (the
///   failed one unfolded).
///
/// Written after each run (and while running, the pages then reload
/// themselves), `dtk ci report` writes them all.
class HostCiReport {
  /// Host CI.
  final HostCi hostCi;

  /// Creates the report of [hostCi].
  HostCiReport(this.hostCi);

  /// The report folder.
  String get dir => p.join(hostCi.dir, 'report');

  /// The global report page.
  String get indexPath => p.join(dir, 'index.html');

  /// The page of a run.
  String runPath(int runId) => p.join(dir, 'runs', '$runId.html');

  /// The page of a project.
  String projectPath(String projectId) =>
      p.join(dir, 'projects', '${_safeName(projectId)}.html');

  /// Write the global report, returns its path.
  Future<String> writeIndex({
    HostCiProjects? projects,
    HostCiQueueState? queue,
  }) async {
    projects ??= await hostCi.getProjects(cachedGit: true);
    queue ??= await hostCi.getQueue();
    await _write(indexPath, _indexHtml(projects, queue));
    return indexPath;
  }

  /// Write the page of a project, returns its path.
  Future<String> writeProject(
    DbHostCiProject project, {
    List<DbHostCiRun>? runs,
  }) async {
    runs ??= await hostCi.getRuns(project.id);
    var path = projectPath(project.id);
    await _write(path, _projectHtml(project, runs));
    return path;
  }

  /// The Markdown report of a run (for an LLM), next to its page.
  String runMarkdownPath(int runId) => p.join(dir, 'runs', '$runId.md');

  /// Write the page of a run and its Markdown report, returns the page path.
  Future<String> writeRun(DbHostCiRun run, {DbHostCiProject? project}) async {
    var lines = await hostCi.readLog(run);
    var path = runPath(run.id);
    await _write(path, _runHtml(run, project: project, lines: lines));
    var projectId = run.project.v ?? '';
    await _write(
      runMarkdownPath(run.id),
      hostCiRunMarkdownText(
        run,
        project: project ?? await hostCi.store.getProject(projectId),
        runs: await hostCi.getRuns(projectId),
        lines: lines,
        logPath: run.log.v == null ? null : p.join(hostCi.logsDir, run.log.v),
        reportPath: path,
        now: hostCi.now(),
      ),
    );
    return path;
  }

  /// Write the pages of a run that changed: the run, its project, the index.
  Future<void> writeForRun(DbHostCiRun run) async {
    var projectId = run.project.v;
    var project = projectId == null
        ? null
        : await hostCi.store.getProject(projectId);
    await writeRun(run, project: project);
    if (project != null) {
      await writeProject(project);
    }
    await writeIndex();
  }

  /// Write every page, returns the index path.
  Future<String> writeAll() async {
    var projects = await hostCi.getProjects();
    var snapshot = await hostCi.store.getSnapshot();
    for (var status in projects.statuses) {
      var runs = snapshot.runsOf(status.project.id);
      await writeProject(status.project, runs: runs);
      for (var run in runs) {
        await writeRun(run, project: status.project);
      }
    }
    return await writeIndex(projects: projects);
  }

  Future<void> _write(String path, String html) async {
    var file = File(path);
    await file.parent.create(recursive: true);
    var tmp = File('$path.$pid.tmp');
    await tmp.writeAsString(html, flush: true);
    await tmp.rename(path);
  }

  String _indexHtml(HostCiProjects projects, HostCiQueueState queue) {
    var now = hostCi.now();
    var live =
        queue.running != null ||
        queue.waiting.isNotEmpty ||
        projects.statuses.any((status) => status.isRunning);
    var sb = StringBuffer();
    _head(
      sb,
      title: 'Host CI',
      refresh: live,
      subtitle:
          '${_e(Platform.localHostname)} · ${_time(now)} · '
          '${projects.statuses.length} projects',
    );
    // The queue.
    sb.writeln('<h2>Queue</h2>');
    if (queue.isEmpty) {
      sb.writeln('<p class="muted">Nothing runs.</p>');
    } else {
      sb.writeln('<ul class="queue">');
      var running = queue.running;
      if (running != null) {
        sb.writeln(
          '<li>${_chip('running', 'run')} '
          '${_projectLink(running.project, '')} '
          '${running.runId == null ? '' : '<a href="runs/${running.runId}.html">run ${running.runId}</a> '}'
          '<span class="muted">${_e(running.client ?? '')} pid ${running.pid}, '
          'started ${_e(hostCiTimeAgo(running.time, now: now))}</span></li>',
        );
      }
      for (var entry in queue.waiting) {
        sb.writeln(
          '<li>${_chip('waiting', 'pend')} '
          '${_projectLink(entry.project, '')} '
          '<span class="muted">${_e(entry.trigger)}, ${_e(entry.client ?? '')} '
          'pid ${entry.pid}, asked ${_e(hostCiTimeAgo(entry.time, now: now))}'
          '</span></li>',
        );
      }
      sb.writeln('</ul>');
    }
    // The open failure reports.
    var failures = projects.failures;
    sb.writeln('<h2>Failure reports (${failures.length})</h2>');
    if (failures.isEmpty) {
      sb.writeln(
        '<p class="muted">None: every red run was validated or '
        'went green again.</p>',
      );
    } else {
      sb.writeln(
        '<table><tr><th>Project</th><th>Status</th><th>Step</th>'
        '<th>Since</th><th>Run</th></tr>',
      );
      for (var status in failures) {
        var run = status.openFailure!;
        var first = status.openFailures.first;
        var step = run.failedStep;
        sb.writeln(
          '<tr><td>${_projectLink(status.project.id, '', name: status.project.name.v)}</td>'
          '<td>${_runChip(run)}</td>'
          '<td>${step == null ? _e(run.error.v ?? '') : _stepFailure(step)}</td>'
          '<td>${_e(hostCiTimeAgo(first.startDateTime ?? now, now: now))}'
          '${status.openFailures.length > 1 ? ' · ${status.openFailures.length} runs' : ''}</td>'
          '<td><a href="runs/${run.id}.html">run ${run.id}</a></td></tr>',
        );
      }
      sb.writeln('</table>');
      sb.writeln(
        '<p class="muted">Kept until a green run, or <code>dtk ci validate '
        '&lt;project&gt;</code>.</p>',
      );
    }
    // The projects.
    var next = projects.next;
    sb.writeln('<h2>Projects</h2>');
    sb.writeln(
      '<table><tr><th>Project</th><th>Last run</th><th>Steps</th>'
      '<th>Next</th></tr>',
    );
    for (var status in projects.statuses) {
      var run = status.lastRun;
      sb.write(
        '<tr><td>${_projectLink(status.project.id, '', name: status.project.name.v)}'
        '<div class="muted small">${_e(status.project.optionsSummary)}</div></td>',
      );
      if (run == null) {
        sb.write('<td>${_chip('never run', 'pend')}</td><td></td>');
      } else {
        sb.write(
          '<td>${_runChip(run)} <a href="runs/${run.id}.html">'
          '${_e(_runWhen(run, now))}</a>'
          '<div class="muted small">${_e(_runFacts(run))}</div></td>'
          '<td>${_stepChips(run)}</td>',
        );
      }
      sb.writeln(
        '<td>${status == next ? '<b>next</b> · ' : ''}'
        '<span class="muted">${_e(status.bucket.label)}: ${_e(status.reason)}</span></td></tr>',
      );
    }
    sb.writeln('</table>');
    _foot(sb);
    return sb.toString();
  }

  String _projectHtml(DbHostCiProject project, List<DbHostCiRun> runs) {
    var now = hostCi.now();
    var sb = StringBuffer();
    _head(
      sb,
      title: project.name.v ?? project.id,
      refresh: runs.any((run) => run.isRunning),
      subtitle: '${_e(project.id)} · ${_e(project.path.v ?? '')}',
      up: '../index.html',
    );
    var options = project.optionsSummary;
    sb.writeln(
      '<p>Steps: ${project.enabledSteps.map((step) => _e(step.label)).join(' → ')}'
      '${options.isEmpty ? '' : '<br>Options: ${_e(options)}'}'
      '${project.isPaused ? '<br>${_chip('skipped', 'skip')}' : ''}</p>',
    );
    var open = hostCiOpenFailureRuns(runs).map((run) => run.id).toSet();
    sb.writeln(
      '<table><tr><th>Run</th><th>Status</th><th>When</th>'
      '<th>Steps</th><th>Commit</th></tr>',
    );
    for (var run in runs.reversed) {
      sb.writeln(
        '<tr><td><a href="../runs/${run.id}.html">${run.id}</a></td>'
        '<td>${_runChip(run)}${open.contains(run.id) ? ' ${_chip('open', 'ko')}' : ''}</td>'
        '<td>${_e(_runWhen(run, now))}</td><td>${_stepChips(run)}</td>'
        '<td class="muted small">${_e(_runFacts(run))}</td></tr>',
      );
    }
    sb.writeln('</table>');
    _foot(sb);
    return sb.toString();
  }

  String _runHtml(
    DbHostCiRun run, {
    DbHostCiProject? project,
    required List<HostCiOutputLine> lines,
  }) {
    var now = hostCi.now();
    var projectId = run.project.v ?? '';
    var sb = StringBuffer();
    _head(
      sb,
      title: '${project?.name.v ?? projectId} · run ${run.id}',
      refresh: run.isRunning,
      subtitle:
          '${_runChip(run)} ${_e(_runWhen(run, now))} · '
          '<a href="../projects/${_safeName(projectId)}.html">${_e(projectId)}</a>',
      up: '../index.html',
    );
    sb.writeln('<table class="facts">');
    void fact(String name, String? value) {
      if (value != null && value.isNotEmpty) {
        sb.writeln('<tr><th>${_e(name)}</th><td>${_e(value)}</td></tr>');
      }
    }

    fact('Retry', _retryText(run));
    fact('Path', run.path.v);
    fact(
      'Commit',
      [
        run.head.v,
        if (run.branch.v != null) '(${run.branch.v})',
      ].whereType<String>().join(' '),
    );
    fact(
      'Tree',
      run.dirty.v == null
          ? null
          : run.isDirty
          ? '${run.dirty.v} modified files'
          : 'clean',
    );
    fact('Ahead', run.ahead.v?.toString());
    fact(
      'Started',
      run.startDateTime == null ? null : _time(run.startDateTime!),
    );
    fact(
      'Duration',
      run.durationValue == null
          ? null
          : hostCiFormatDuration(run.durationValue!),
    );
    fact(
      'Trigger',
      [run.trigger.v, run.client.v].whereType<String>().join(', '),
    );
    fact(
      'Tools',
      [
        if (run.dartVersion.v != null) 'dart ${run.dartVersion.v}',
        if (run.flutterVersion.v != null) 'flutter ${run.flutterVersion.v}',
        if (run.runCiVersion.v != null) 'run_ci ${run.runCiVersion.v}',
      ].join(', '),
    );
    fact('Error', run.error.v);
    fact(
      'Validated',
      run.validatedDateTime == null ? null : _time(run.validatedDateTime!),
    );
    sb.writeln('</table>');
    sb.writeln(
      '<p>For Claude (or any LLM): <a href="${run.id}.md">the Markdown '
      'report</a> (the steps, their commands, the failure logs), or '
      '<code>dtk ci context ${run.id} --copy</code></p>',
    );
    var failed = run.failedStep?.retryStepName;
    if (failed != null) {
      sb.writeln(
        '<p>Re-run from the failed step: <code>dtk ci run '
        '${_e(projectId)} --from ${_stepArg(failed)}</code></p>',
      );
    }

    // The steps, each with its log section.
    var sections = hostCiLogSections(lines);
    HostCiLogSection? sectionOf(HostCiStepName? step) {
      for (var section in sections) {
        if (section.step == step) {
          return section;
        }
      }
      return null;
    }

    var prelude = sectionOf(null);
    if (prelude != null) {
      sb.writeln('<details><summary>Set up</summary>');
      _log(sb, prelude.lines);
      sb.writeln('</details>');
    }
    for (var step in run.stepList) {
      var section = sectionOf(step.stepName);
      var duration = step.durationValue;
      var open = step.isFailed || step.stepStatus == HostCiStepStatus.running;
      sb.writeln(
        '<details${open ? ' open' : ''}><summary>'
        '${_stepChip(step)} ${_e(step.label)}'
        '${duration == null ? '' : ' <span class="muted">${hostCiFormatDuration(duration)}</span>'}'
        '${step.isFailed ? ' · ${_stepFailure(step)}' : ''}'
        '</summary>',
      );
      var stepName = step.retryStepName;
      if (stepName != null) {
        sb.writeln(
          '<p class="muted small retry">Exit code ${step.exitCode.v ?? '-'}'
          '${step.policy.v == null ? '' : ' · policy ${_e(step.policy.v!)}'}'
          ' · retry: <code>dtk ci run ${_e(projectId)} --step '
          '${_stepArg(stepName)}</code></p>',
        );
      }
      if (section == null) {
        sb.writeln('<p class="muted">No log.</p>');
      } else {
        _log(sb, section.lines);
      }
      sb.writeln('</details>');
    }
    if (lines.isEmpty) {
      sb.writeln('<p class="muted">The log file is gone (retention).</p>');
    }
    _foot(sb);
    return sb.toString();
  }

  void _log(StringBuffer sb, List<HostCiOutputLine> lines) {
    sb.write('<pre class="log">');
    for (var line in lines) {
      var cls = line.isError
          ? 'err'
          : line.text.startsWith(hostCiPackageMarker)
          ? 'pkg'
          : line.text.startsWith(hostCiCommandMarker)
          ? 'cmd'
          : null;
      if (cls == null) {
        sb.writeln(_e(line.text));
      } else {
        sb.writeln('<span class="$cls">${_e(line.text)}</span>');
      }
    }
    sb.writeln('</pre>');
  }

  String _projectLink(String projectId, String prefix, {String? name}) =>
      '<a href="${prefix}projects/${_safeName(projectId)}.html" '
      'title="${_e(projectId)}">${_e(name ?? projectId)}</a>';

  String _runWhen(DbHostCiRun run, DateTime now) {
    var start = run.startDateTime;
    var duration = run.durationValue;
    return [
      if (start != null) hostCiTimeAgo(start, now: now),
      if (duration != null) hostCiFormatDuration(duration),
    ].join(' · ');
  }

  String _runFacts(DbHostCiRun run) => [
    ?_retryText(run),
    if (run.shortHead.isNotEmpty) run.shortHead,
    if (run.dirty.v != null)
      if (run.isDirty) 'dirty ${run.dirty.v}' else 'clean',
    if ((run.ahead.v ?? 0) > 0) '↑${run.ahead.v}',
    if (run.client.v != null) run.client.v!,
  ].join(' · ');

  /// `retry from analyze`, `retry only format`, null for a full run.
  String? _retryText(DbHostCiRun run) => switch (run.partialValue) {
    HostCiPartial.from => 'retry from ${run.firstStepName?.label ?? '?'}',
    HostCiPartial.only =>
      'retry only ${run.stepList.map((step) => step.label).join(', ')}',
    null => null,
  };

  /// The `dtk ci run` argument naming [step] (`test-web`, `downgrade`).
  String _stepArg(HostCiStepName step) =>
      step.isDowngrade ? 'downgrade' : step.label.replaceAll(' ', '-');

  String _runChip(DbHostCiRun run) {
    var cls = switch (run.runStatus) {
      HostCiRunStatus.success => 'ok',
      HostCiRunStatus.failure || HostCiRunStatus.error => 'ko',
      HostCiRunStatus.warning => 'warn',
      HostCiRunStatus.running => 'run',
      HostCiRunStatus.cancelled => 'skip',
    };
    return _chip(hostCiRunStatusText(run), cls);
  }

  String _stepChip(DbHostCiStep step) {
    var (text, cls) = switch (step.stepStatus) {
      HostCiStepStatus.success => ('✓', 'ok'),
      HostCiStepStatus.failure =>
        step.isWarning
            ? ('!', 'warn')
            : step.isAcceptedFailure
            ? ('✓', 'acc')
            : ('✗', 'ko'),
      HostCiStepStatus.running => ('◐', 'run'),
      HostCiStepStatus.pending => ('·', 'pend'),
      HostCiStepStatus.skipped => ('–', 'skip'),
      HostCiStepStatus.cancelled => ('⊘', 'skip'),
    };
    return '<span class="chip $cls" title="${_e(step.label)}: '
        '${_e(step.statusLabel)}">$text</span>';
  }

  String _stepChips(DbHostCiRun run) => run.stepList
      .map((step) {
        var duration = step.durationValue;
        return '<span class="step" title="${_e(step.label)}: '
            '${_e(step.statusLabel)}">${_stepChip(step)}'
            '<span class="small">${_e(_shortLabel(step))}'
            '${duration == null ? '' : ' ${hostCiFormatDuration(duration)}'}'
            '</span></span>';
      })
      .join(' ');

  String _shortLabel(DbHostCiStep step) => switch (step.stepName) {
    HostCiStepName.pubUpgrade => 'upgrade',
    HostCiStepName.pubGet => 'get',
    HostCiStepName.pubDowngrade => 'downgrade',
    HostCiStepName.analyzeDowngrade => 'analyze↓',
    HostCiStepName.testHost => 'test host',
    HostCiStepName.testWeb => 'test web',
    HostCiStepName.pubRestore => 'restore',
    _ => step.label,
  };

  String _stepFailure(DbHostCiStep step) => [
    '<b>${_e(step.label)}</b> ${_e(step.statusLabel)}',
    if (step.failedPackage.v != null)
      'in <code>${_e(step.failedPackage.v!)}</code>',
    if (step.failedCommand.v != null)
      '<span class="muted small">${_e(step.failedCommand.v!)}</span>',
  ].join(' ');

  String _chip(String text, String cls) =>
      '<span class="chip $cls">${_e(text)}</span>';

  void _head(
    StringBuffer sb, {
    required String title,
    required bool refresh,
    String? subtitle,
    String? up,
  }) {
    sb.writeln('<!doctype html><html lang="en"><head><meta charset="utf-8">');
    sb.writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1">',
    );
    if (refresh) {
      sb.writeln('<meta http-equiv="refresh" content="3">');
    }
    sb.writeln('<title>${_e(title)}</title><style>$_css</style></head><body>');
    sb.writeln(
      '<header>${up == null ? '' : '<a href="$up">Host CI</a> / '}'
      '<h1>${_e(title)}</h1></header>',
    );
    if (subtitle != null) {
      sb.writeln('<p class="muted">$subtitle</p>');
    }
  }

  void _foot(StringBuffer sb) {
    sb.writeln(
      '<footer class="muted small">Generated ${_time(hostCi.now())} by '
      'Host CI (dtk ci).</footer></body></html>',
    );
  }
}

String _time(DateTime time) {
  String pad(int value) => value.toString().padLeft(2, '0');
  var local = time.toLocal();
  return '${local.year}-${pad(local.month)}-${pad(local.day)} '
      '${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
}

String _safeName(String id) => id.replaceAll(RegExp(r'[^\w.-]'), '_');

String _e(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

const _css = '''
:root { --bg: #fff; --fg: #1f2328; --muted: #656d76; --line: #d0d7de;
  --ok: #1a7f37; --ko: #cf222e; --warn: #9a6700; --run: #0969da;
  --code: #f6f8fa; }
@media (prefers-color-scheme: dark) { :root { --bg: #0d1117; --fg: #e6edf3;
  --muted: #8d96a0; --line: #30363d; --ok: #3fb950; --ko: #f85149;
  --warn: #d29922; --run: #58a6ff; --code: #161b22; } }
body { background: var(--bg); color: var(--fg); margin: 0 auto;
  max-width: 1200px; padding: 16px; font: 14px/1.5 system-ui, sans-serif; }
a { color: var(--run); text-decoration: none; } a:hover { text-decoration: underline; }
header { display: flex; gap: 8px; align-items: baseline; }
h1 { font-size: 22px; margin: 0; } h2 { font-size: 17px; margin: 24px 0 8px; }
table { border-collapse: collapse; width: 100%; }
th, td { border-bottom: 1px solid var(--line); padding: 6px 8px;
  text-align: left; vertical-align: top; }
table.facts { width: auto; } table.facts th { color: var(--muted); font-weight: normal; }
.muted { color: var(--muted); } .small { font-size: 12px; }
.chip { display: inline-block; padding: 0 6px; border-radius: 10px;
  border: 1px solid currentColor; font-size: 12px; white-space: nowrap; }
.ok { color: var(--ok); } .ko { color: var(--ko); } .warn { color: var(--warn); }
.run { color: var(--run); } .acc { color: var(--ok); opacity: .6; }
.skip, .pend { color: var(--muted); }
.step { display: inline-flex; gap: 3px; align-items: center; margin-right: 6px; }
details { border: 1px solid var(--line); border-radius: 6px; margin: 8px 0; }
summary { cursor: pointer; padding: 6px 10px; }
pre.log { background: var(--code); margin: 0; padding: 8px 10px;
  overflow-x: auto; font: 12px/1.45 ui-monospace, "JetBrains Mono", monospace; }
pre.log .err { color: var(--ko); } pre.log .pkg { color: var(--run); font-weight: bold; }
pre.log .cmd { color: var(--muted); }
p.retry { margin: 4px 10px; }
ul.queue { padding-left: 18px; } code { background: var(--code); padding: 0 4px; }
footer { margin-top: 32px; }
''';
