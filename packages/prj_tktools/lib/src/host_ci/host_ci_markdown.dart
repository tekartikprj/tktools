import 'package:tekartik_prj_tktools/src/host_ci/host_ci.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_model.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_runner.dart';

/// Default number of log lines kept per failed step in a Markdown report.
const hostCiMarkdownMaxLines = 200;

/// The Markdown report of [run], to paste to an LLM (or a human): what was
/// run where (checkout, commit, tools, options), every step with its exact
/// command, status, duration and exit code, the log of each failure (the part
/// of the failing package, [maxLines] at most per step; every step entirely
/// with [fullLog]), the retry commands and the last runs of the project.
Future<String> hostCiRunMarkdown(
  HostCi hostCi,
  DbHostCiRun run, {
  bool fullLog = false,
  int maxLines = hostCiMarkdownMaxLines,
}) async {
  var projectId = run.project.v ?? '';
  return hostCiRunMarkdownText(
    run,
    project: await hostCi.store.getProject(projectId),
    runs: await hostCi.getRuns(projectId),
    lines: await hostCi.readLog(run),
    logPath: run.log.v == null ? null : '${hostCi.logsDir}/${run.log.v}',
    reportPath: hostCi.report.runPath(run.id),
    now: hostCi.now(),
    fullLog: fullLog,
    maxLines: maxLines,
  );
}

/// [hostCiRunMarkdown] from the data: the [project] (null when removed), its
/// [runs] (the oldest first, for the history and the open reports) and the
/// [lines] of the log of [run].
String hostCiRunMarkdownText(
  DbHostCiRun run, {
  required DbHostCiProject? project,
  required List<DbHostCiRun> runs,
  required List<HostCiOutputLine> lines,
  String? logPath,
  String? reportPath,
  required DateTime now,
  bool fullLog = false,
  int maxLines = hostCiMarkdownMaxLines,
}) {
  var projectId = run.project.v ?? '';
  var sb = StringBuffer();
  var sections = hostCiLogSections(lines);
  HostCiLogSection? sectionOf(DbHostCiStep step) {
    for (var section in sections) {
      if (section.step != null
          ? section.step == step.stepName
          : section.title == step.label) {
        return section;
      }
    }
    return null;
  }

  // The exact command of a step: the first `$` line of its log section (the
  // runner writes it), else rebuilt.
  String? commandOf(DbHostCiStep step) {
    var section = sectionOf(step);
    for (var line in section?.lines ?? const <HostCiOutputLine>[]) {
      if (line.text.startsWith(hostCiCommandMarker)) {
        return line.text.substring(hostCiCommandMarker.length);
      }
    }
    var stepName = step.stepName;
    if (stepName != null && project != null) {
      return hostCiStepCommand(project, stepName);
    }
    return null;
  }

  var open = HostCiVerdicts(runs).open;
  var isOpen = open.any((openRun) => openRun.id == run.id);
  sb.writeln(
    '# Host CI run ${run.id}: $projectId, ${hostCiRunStatusText(run)}',
  );
  sb.writeln();
  sb.writeln(
    'Host CI runs the CI of a local checkout with `dev_build`\'s `run_ci`, '
    'one process per step in the repository root, the steps in order, a '
    'failing step skipping the next ones (unless its policy is warn or '
    'accept). `run_ci --recursive` runs the action in every dart/flutter '
    'package below the root (`# package: <path>` lines in the log, `\$` for '
    'each command).',
  );
  sb.writeln();
  void fact(String name, String? value) {
    if (value != null && value.isNotEmpty) {
      sb.writeln('- $name: $value');
    }
  }

  fact('Project', '$projectId (${project?.name.v ?? 'removed'})');
  fact('Checkout', run.path.v);
  fact(
    'Commit',
    [
      if (run.head.v != null) run.head.v!,
      if (run.branch.v != null) '(${run.branch.v})',
      if (run.commitTime.v != null)
        'committed ${_time(DateTime.fromMillisecondsSinceEpoch(run.commitTime.v!))}',
    ].join(' '),
  );
  fact(
    'Working tree',
    run.dirty.v == null
        ? null
        : [
            if (run.isDirty) '${run.dirty.v} modified files' else 'clean',
            if (run.ahead.v != null) '${run.ahead.v} commits ahead',
          ].join(', '),
  );
  fact(
    'Run',
    [
      if (run.startDateTime != null) 'started ${_time(run.startDateTime!)}',
      if (run.durationValue != null)
        'took ${hostCiFormatDuration(run.durationValue!)}',
      'trigger ${run.trigger.v}',
      if (run.client.v != null) 'by ${run.client.v}',
      if (run.partialValue == HostCiPartial.from)
        'retry from ${run.firstStepName?.label}',
      if (run.partialValue == HostCiPartial.only) 'retry of some steps only',
    ].join(', '),
  );
  fact(
    'Tools',
    [
      if (run.dartVersion.v != null) 'dart ${run.dartVersion.v}',
      if (run.flutterVersion.v != null) 'flutter ${run.flutterVersion.v}',
      if (run.runCiVersion.v != null)
        'run_ci (dev_build) ${run.runCiVersion.v}',
    ].join(', '),
  );
  var options = project?.optionsSummary ?? '';
  fact('Options', options.isEmpty ? 'default' : options);
  fact('Error', run.error.v);
  if (run.isFailureReport) {
    fact(
      'Report',
      run.isValidated
          ? 'validated ${_time(run.validatedDateTime!)}'
          : isOpen
          ? 'open (${open.length} red or warning run${open.length > 1 ? 's' : ''} '
                'since ${_time(open.first.startDateTime ?? now)})'
          : 'closed by a later green run',
    );
  }
  fact('Log file', logPath);
  fact('Web page', reportPath);

  // The steps.
  sb.writeln();
  sb.writeln('## Steps');
  sb.writeln();
  sb.writeln(
    '| # | Step | Status | Duration | Exit code | Failing package | Command |',
  );
  sb.writeln('| --- | --- | --- | --- | --- | --- | --- |');
  var index = 0;
  for (var step in run.stepList) {
    index++;
    var duration = step.durationValue;
    var command = commandOf(step);
    sb.writeln(
      '| $index | ${step.label} | ${step.statusLabel} | '
      '${duration == null ? '' : hostCiFormatDuration(duration)} | '
      '${step.exitCode.v ?? ''} | '
      '${step.isFailed ? _cell(step.failedPackage.v) : ''} | '
      '${command == null ? '' : '`${_cell(command)}`'} |',
    );
  }

  // The failures, with their log.
  var failed = run.stepList.where((step) => step.isFailed).toList();
  if (failed.isNotEmpty) {
    sb.writeln();
    sb.writeln('## Failures');
    for (var step in failed) {
      sb.writeln();
      sb.writeln(
        '### ${step.label}: ${step.statusLabel}, exit code '
        '${step.exitCode.v ?? '-'}',
      );
      sb.writeln();
      fact('Failing package', step.failedPackage.v);
      fact(
        'Failing command',
        step.failedCommand.v == null ? null : '`${step.failedCommand.v}`',
      );
      fact('Step command', '`${commandOf(step) ?? '?'}`');
      var section = sectionOf(step);
      if (section == null) {
        sb.writeln();
        sb.writeln('(no log)');
        continue;
      }
      var excerpt = fullLog
          ? section.lines
          : _failureExcerpt(section.lines, step.failedPackage.v);
      var testFailures = fullLog
          ? const <List<HostCiOutputLine>>[]
          : _testFailures(excerpt);
      if (excerpt.length > maxLines && testFailures.isNotEmpty) {
        _writeTestFailures(sb, testFailures, excerpt, maxLines: maxLines);
        continue;
      }
      _writeLog(
        sb,
        excerpt,
        maxLines: fullLog ? null : maxLines,
        title: excerpt.length == section.lines.length
            ? 'Log of the step'
            : 'Log of the failing package (${excerpt.length} of '
                  '${section.lines.length} lines of the step)',
      );
    }
  }
  if (fullLog) {
    var others = [
      for (var section in sections)
        if (section.step == null && section.title == 'run') section,
    ];
    for (var section in others) {
      _writeLog(sb, section.lines, maxLines: null, title: 'Set up');
    }
  }

  // Retry.
  var retryStep = run.failedStep?.retryStepName;
  sb.writeln();
  sb.writeln('## Retry');
  sb.writeln();
  if (retryStep != null) {
    sb.writeln(
      '- From the failed step to the end (green, it closes the report): '
      '`dtk ci run $projectId --from ${_stepArg(retryStep)}`',
    );
    sb.writeln(
      '- The failed step only: `dtk ci run $projectId --step '
      '${_stepArg(retryStep)}`',
    );
  }
  sb.writeln('- Everything: `dtk ci run $projectId`');
  sb.writeln(
    '- Full log of a step: `dtk ci log ${run.id} --step <step>` '
    '(`failed` for the failed one)',
  );

  // History.
  var history = runs.reversed.take(6).toList();
  if (history.length > 1) {
    sb.writeln();
    sb.writeln('## Last runs of the project');
    sb.writeln();
    sb.writeln('| Run | Started | Status | Failed step | Commit | Tree |');
    sb.writeln('| --- | --- | --- | --- | --- | --- |');
    for (var other in history) {
      var step = other.failedStep;
      sb.writeln(
        '| ${other.id}${other.id == run.id ? ' (this one)' : ''} | '
        '${other.startDateTime == null ? '' : _time(other.startDateTime!)} | '
        '${hostCiRunStatusText(other)}'
        '${other.partialValue == null ? '' : ', retry'} | '
        '${step == null ? '' : '${step.label}${step.failedPackage.v == null ? '' : ' in ${_cell(step.failedPackage.v)}'}'} | '
        '${other.shortHead} | '
        '${other.dirty.v == null ? '' : (other.isDirty ? 'dirty ${other.dirty.v}' : 'clean')} |',
      );
    }
  }
  return sb.toString();
}

/// The lines of the failing package in a step log: from its `# package:`
/// line to the next one, plus the end of the step (the `run_ci failed`
/// summary); the whole step when the package is unknown.
List<HostCiOutputLine> _failureExcerpt(
  List<HostCiOutputLine> lines,
  String? package,
) {
  if (package == null) {
    return lines;
  }
  var start = -1;
  for (var i = 0; i < lines.length; i++) {
    var text = lines[i].text;
    if (text.startsWith(hostCiPackageMarker) &&
        _samePackage(text.substring(hostCiPackageMarker.length), package)) {
      start = i;
      break;
    }
  }
  if (start < 0) {
    return lines;
  }
  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (lines[i].text.startsWith(hostCiPackageMarker)) {
      end = i;
      break;
    }
  }
  var excerpt = [lines.first, ...lines.sublist(start, end)];
  // The summary after the last package (run_ci failed ...).
  var lastPackage = lines.lastIndexWhere(
    (line) => line.text.startsWith(hostCiPackageMarker),
  );
  if (lastPackage >= end) {
    var tailStart = lines.indexWhere(
      (line) =>
          line.isError &&
          (line.text.contains('run_ci failed') || line.text.startsWith('###')),
      lastPackage,
    );
    if (tailStart >= 0) {
      excerpt.add(const HostCiOutputLine('[...]'));
      excerpt.addAll(lines.sublist(tailStart));
    }
  }
  return excerpt;
}

/// A `dart test` / `flutter test` progress line (`00:12 +3 ~1 -2: ...`).
final _testProgress = RegExp(r'^\d+:\d+ \+\d+');

/// The failing tests of a test log: each `[E]` progress line with the lines
/// that follow it (the error, the stack) up to the next progress line.
List<List<HostCiOutputLine>> _testFailures(List<HostCiOutputLine> lines) {
  var blocks = <List<HostCiOutputLine>>[];
  List<HostCiOutputLine>? current;
  for (var line in lines) {
    if (_testProgress.hasMatch(line.text)) {
      current = null;
      if (line.text.trimRight().endsWith('[E]')) {
        current = [line];
        blocks.add(current);
      }
    } else {
      current?.add(line);
    }
  }
  return blocks;
}

/// The test name of an `[E]` line: what follows the progress prefix.
String _testName(String line) {
  var text = line.trimRight();
  if (text.endsWith('[E]')) {
    text = text.substring(0, text.length - 3).trimRight();
  }
  var colon = text.indexOf(': ');
  return colon < 0 ? text : text.substring(colon + 2);
}

/// The failing tests of a long test log: their names, the errors in order
/// (the same error once), the end of the log; [maxLines] at most.
void _writeTestFailures(
  StringBuffer sb,
  List<List<HostCiOutputLine>> blocks,
  List<HostCiOutputLine> lines, {
  required int maxLines,
}) {
  sb.writeln();
  sb.writeln('Failing tests (${blocks.length}, in the order they failed):');
  sb.writeln();
  for (var block in blocks.take(100)) {
    sb.writeln('- ${_testName(block.first.text)}');
  }
  if (blocks.length > 100) {
    sb.writeln('- ... ${blocks.length - 100} more');
  }
  sb.writeln();
  sb.writeln(
    'Their errors (stderr lines start with `! `, a repeated error is '
    'written once):',
  );
  sb.writeln();
  sb.writeln('```text');
  var seen = <String, String>{};
  var budget = maxLines;
  var skipped = 0;
  for (var block in blocks) {
    var name = _testName(block.first.text);
    var body = block.skip(1).map((line) => line.text.trim()).join('\n');
    var first = seen[body];
    if (first != null) {
      if (budget > 0) {
        sb.writeln('${block.first.text}  (same error as "$first")');
        budget--;
      } else {
        skipped++;
      }
      continue;
    }
    seen[body] = name;
    if (budget < block.length) {
      skipped++;
      continue;
    }
    for (var line in block) {
      sb.writeln(line.isError ? '! ${line.text}' : line.text);
    }
    budget -= block.length;
  }
  if (skipped > 0) {
    sb.writeln('[... $skipped more failing tests omitted ...]');
  }
  sb.writeln('```');
  var tail = lines.length > 20 ? lines.sublist(lines.length - 20) : lines;
  _writeLog(sb, tail, maxLines: null, title: 'End of the log');
}

bool _samePackage(String a, String b) {
  String normalize(String path) {
    var text = path.trim();
    if (text.startsWith('./')) {
      text = text.substring(2);
    }
    return text.endsWith('/') ? text.substring(0, text.length - 1) : text;
  }

  return normalize(a) == normalize(b);
}

void _writeLog(
  StringBuffer sb,
  List<HostCiOutputLine> lines, {
  required int? maxLines,
  required String title,
}) {
  var shown = lines;
  var omitted = 0;
  if (maxLines != null && lines.length > maxLines) {
    // The start (the command) and the end (the error, the summary).
    var head = maxLines ~/ 4;
    var tail = maxLines - head;
    omitted = lines.length - maxLines;
    shown = [
      ...lines.sublist(0, head),
      HostCiOutputLine('[... $omitted lines omitted ...]'),
      ...lines.sublist(lines.length - tail),
    ];
  }
  sb.writeln();
  sb.writeln('$title (stderr lines start with `! `):');
  sb.writeln();
  sb.writeln('```text');
  for (var line in shown) {
    sb.writeln(line.isError ? '! ${line.text}' : line.text);
  }
  sb.writeln('```');
}

String _cell(String? text) => (text ?? '').replaceAll('|', r'\|');

String _stepArg(HostCiStepName step) =>
    step.isDowngrade ? 'downgrade' : step.label.replaceAll(' ', '-');

String _time(DateTime time) {
  String pad(int value) => value.toString().padLeft(2, '0');
  var local = time.toLocal();
  return '${local.year}-${pad(local.month)}-${pad(local.day)} '
      '${pad(local.hour)}:${pad(local.minute)}';
}
