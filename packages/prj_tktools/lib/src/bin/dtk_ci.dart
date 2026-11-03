import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:process_run/shell.dart' show whichSync;
import 'package:tekartik_prj_tktools/host_ci.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:tekartik_prj_tktools/src/utils.dart' show tkPubFindGitTop;

/// The Host CI folder option.
const dtkCiOptionDir = 'dir';

/// The client name of the runs of the command line.
const dtkCiClient = 'dtk ci';

const _flagJson = 'json';
const _flagNext = 'next';
const _flagAllDue = 'all-due';
const _flagQuiet = 'quiet';
const _flagOpen = 'open';
const _flagAll = 'all';
const _flagPubGetOnly = 'pub-get-only';
const _flagFull = 'full';
const _flagCopy = 'copy';
const _optionMaxLines = 'max-lines';
const _optionRun = 'run';
const _optionStep = 'step';
const _optionFrom = 'from';
const _optionPlatform = 'platform';
const _optionSeverity = 'severity';

/// `dtk ci`: Host CI from the command line, the CI of local checkouts run on
/// this machine, shared with the apps reading the same folder.
class DtkCiCommand extends ShellBinCommand {
  /// dtk ci command
  DtkCiCommand()
    : super(
        name: 'ci',
        description:
            'Host CI: run the CI of local checkouts on this machine (pub '
            'upgrade, analyze, format, test, build, downgrade analyze), '
            'reports and web pages',
        parser: ArgParser(allowTrailingOptions: true),
      ) {
    parser.addOption(
      dtkCiOptionDir,
      help:
          'Host CI folder (default: $hostCiDirEnvKey or ~/.config/tekartik/host_ci)',
    );
    addCommand(_CiStatusCommand());
    addCommand(_CiNextCommand());
    addCommand(_CiRunCommand());
    addCommand(_CiFailuresCommand());
    addCommand(_CiValidateCommand());
    addCommand(_CiLogCommand());
    addCommand(_CiContextCommand());
    addCommand(_CiReportCommand());
    addCommand(_CiQueueCommand());
    addCommand(_CiAddCommand());
    addCommand(_CiRemoveCommand());
    addCommand(_CiSkipCommand(skip: true));
    addCommand(_CiSkipCommand(skip: false));
    addCommand(_CiPolicyCommand());
    addCommand(_CiStepsCommand());
  }

  @override
  FutureOr<bool> onRun() async {
    // `dtk ci` alone: the status.
    await _withHostCi(results.option(dtkCiOptionDir), (hostCi) async {
      _printStatuses(await hostCi.getProjects());
    });
    return true;
  }
}

Future<T> _withHostCi<T>(
  String? dir,
  Future<T> Function(HostCi hostCi) action,
) async {
  var hostCi = await HostCi.open(dir: dir, client: dtkCiClient);
  try {
    return await action(hostCi);
  } finally {
    await hostCi.close();
  }
}

abstract class _CiSubCommand extends ShellBinCommand {
  _CiSubCommand({
    required super.name,
    required super.description,
    bool withJson = true,
  }) : super(parser: ArgParser(allowTrailingOptions: true)) {
    if (withJson) {
      parser.addFlag(_flagJson, help: 'Json output', negatable: false);
    }
  }

  bool get jsonOutput =>
      parser.options.containsKey(_flagJson) && results.flag(_flagJson);

  String? get _dir => (parent as DtkCiCommand).results.option(dtkCiOptionDir);

  /// Run [action] on Host CI, closed afterwards.
  Future<T> withHostCi<T>(Future<T> Function(HostCi hostCi) action) =>
      _withHostCi(_dir, action);

  /// The project matching the argument [query], throws when none.
  Future<DbHostCiProject> findProject(HostCi hostCi, String query) async {
    var projects = await hostCi.store.getProjects();
    var project = hostCiFindProject(projects, query);
    if (project == null) {
      // A path.
      var path = hostCiCanonicalPath(query);
      for (var candidate in projects) {
        if (candidate.path.v == path) {
          return candidate;
        }
      }
      throw StateError('No Host CI project matches "$query"');
    }
    return project;
  }

  /// The single trailing argument.
  String singleArg(String what) {
    var rest = results.rest;
    if (rest.length != 1) {
      throw ArgumentError('One argument expected ($what)');
    }
    return rest.first;
  }

  void writeJson(Object? value) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));
  }
}

String _statusLine(HostCiProjectStatus status, {required bool isNext}) {
  var run = status.lastCompletedRun;
  var failure = status.openFailure;
  return [
    status.project.id,
    status.bucket.label,
    status.reason,
    if (run != null) ...[
      hostCiRunStatusText(run),
      if (run.durationValue != null) hostCiFormatDuration(run.durationValue!),
      if (run.shortHead.isNotEmpty) run.shortHead,
    ],
    if (failure != null) _failureText(failure),
    if (status.isRunning) 'running',
    if (isNext) 'next',
  ].join(' · ');
}

String _failureText(DbHostCiRun run) {
  var step = run.failedStep;
  return [
    'open report: run ${run.id}',
    if (step != null) '${step.label} ${step.statusLabel}',
    if (step?.failedPackage.v != null) 'in ${step!.failedPackage.v}',
    if (step == null && run.error.v != null) run.error.v!,
  ].join(' ');
}

void _printStatuses(HostCiProjects projects) {
  if (projects.isEmpty) {
    stdout.writeln('No project, add one: dtk ci add <path>');
    return;
  }
  var next = projects.next;
  for (var status in projects.statuses) {
    stdout.writeln(_statusLine(status, isNext: status == next));
  }
}

class _CiStatusCommand extends _CiSubCommand {
  _CiStatusCommand()
    : super(
        name: 'status',
        description:
            'The projects, the due ones first, with their last run and open '
            'report (exit code 1 when the given project is red)',
      );

  @override
  FutureOr<bool> onRun() async {
    await withHostCi((hostCi) async {
      var projects = await hostCi.getProjects();
      var statuses = projects.statuses;
      var query = results.rest.firstOrNull;
      if (query != null) {
        var project = await findProject(hostCi, query);
        statuses = statuses
            .where((status) => status.project.id == project.id)
            .toList();
      }
      var next = projects.next;
      if (jsonOutput) {
        writeJson([
          for (var status in statuses)
            hostCiStatusToJson(status, isNext: status == next),
        ]);
      } else if (query == null) {
        _printStatuses(projects);
      } else {
        for (var status in statuses) {
          stdout.writeln(_statusLine(status, isNext: status == next));
        }
      }
      if (query != null && (statuses.single.lastCompletedRun?.isRed ?? false)) {
        exitCode = 1;
      }
    });
    return true;
  }
}

class _CiNextCommand extends _CiSubCommand {
  _CiNextCommand()
    : super(
        name: 'next',
        description:
            'The project to run next and why (nothing runs, see `run`)',
      );

  @override
  FutureOr<bool> onRun() async {
    await withHostCi((hostCi) async {
      var projects = await hostCi.getProjects();
      var next = projects.next;
      if (jsonOutput) {
        writeJson(next == null ? null : hostCiStatusToJson(next, isNext: true));
      } else if (next == null) {
        stdout.writeln('Nothing due');
      } else {
        stdout.writeln('${next.project.id} · ${next.reason}');
      }
    });
    return true;
  }
}

class _CiRunCommand extends _CiSubCommand {
  _CiRunCommand()
    : super(
        name: 'run',
        description:
            'Run projects (the next one by default), after the runs asked '
            'before on this machine; exit code 1 when one is red. Retry: '
            '--step <step> (only it, repeatable) or --from <step> (it and '
            'the next ones), `failed` for the failed step of the last run',
      ) {
    parser.addMultiOption(
      _optionStep,
      help:
          'Only this step: pub-get, pub-upgrade, analyze, format, test-host, '
          'test-web, build-web, build-host, downgrade, test, build, failed',
    );
    parser.addOption(
      _optionFrom,
      help: 'This step and the next ones (or failed)',
    );
    parser.addFlag(
      _flagNext,
      help: 'The next project (the default without project)',
      negatable: false,
    );
    parser.addFlag(
      _flagAllDue,
      help: 'Every due project, one after the other',
      negatable: false,
    );
    parser.addFlag(
      _flagQuiet,
      abbr: 'q',
      help: 'No output, the summary only',
      negatable: false,
    );
  }

  @override
  FutureOr<bool> onRun() async {
    await withHostCi((hostCi) async {
      var queries = results.rest;
      var allDue = results.flag(_flagAllDue);
      var quiet = results.flag(_flagQuiet) || jsonOutput;
      var interrupted = false;
      var sigint = ProcessSignal.sigint.watch().listen((_) {
        if (interrupted) {
          exit(130);
        }
        interrupted = true;
        stderr.writeln('Cancelling (Ctrl-C again to quit at once)');
        hostCi.cancel();
      });
      var runs = <DbHostCiRun>[];
      try {
        Future<void> runOne(
          String projectId,
          HostCiTrigger trigger, {
          List<HostCiStepName>? only,
          HostCiStepName? from,
        }) async {
          if (!quiet) {
            stdout.writeln(
              '# Host CI $projectId'
              '${only == null ? '' : ', only ${only.map((step) => step.label).join(', ')}'}'
              '${from == null ? '' : ', from ${from.label}'}',
            );
          }
          var run = await hostCi.run(
            projectId,
            trigger: trigger,
            only: only,
            from: from,
            onWaiting: quiet
                ? null
                : (state) => stdout.writeln(
                    '# waiting: ${state.running == null ? '' : 'running ${state.running}, '}'
                    '${state.waiting.length} in the queue',
                  ),
            onLines: quiet
                ? null
                : (lines) {
                    for (var line in lines) {
                      (line.isError ? stderr : stdout).writeln(line.text);
                    }
                  },
          );
          runs.add(run);
          if (!jsonOutput) {
            stdout.writeln(
              '# ${hostCiRunSummary(run, projectName: projectId)}'
              '${run.failedStep == null ? '' : ' · ${_failureText(run)}'}',
            );
          }
        }

        var stepOptions = results.multiOption(_optionStep);
        var fromOption = results.option(_optionFrom);
        if (stepOptions.isNotEmpty || fromOption != null) {
          if (queries.length != 1) {
            throw ArgumentError('A retry (--step, --from) needs one project');
          }
          if (stepOptions.isNotEmpty && fromOption != null) {
            throw ArgumentError('--step or --from, not both');
          }
          var project = await findProject(hostCi, queries.single);
          Future<List<HostCiStepName>> parse(String text) async {
            if (text == 'failed') {
              var runs = await hostCi.getRuns(project.id);
              var failed = runs.reversed
                  .map((run) => run.failedStep?.retryStepName)
                  .nonNulls
                  .firstOrNull;
              if (failed == null) {
                throw StateError('No failed step in the runs of ${project.id}');
              }
              return [failed];
            }
            var steps = hostCiStepNamesParse(text);
            if (steps.isEmpty) {
              throw ArgumentError('Unknown step $text');
            }
            return steps;
          }

          if (fromOption != null) {
            await runOne(
              project.id,
              HostCiTrigger.retry,
              from: (await parse(fromOption)).first,
            );
          } else {
            await runOne(
              project.id,
              HostCiTrigger.retry,
              only: [for (var text in stepOptions) ...await parse(text)],
            );
          }
        } else if (queries.isNotEmpty) {
          for (var query in queries) {
            if (interrupted) {
              break;
            }
            var project = await findProject(hostCi, query);
            await runOne(project.id, HostCiTrigger.manual);
          }
        } else if (allDue) {
          var done = <String>{};
          while (!interrupted) {
            // Read again after each run: what is due changes.
            var due = (await hostCi.getProjects()).due
                .where((status) => !done.contains(status.project.id))
                .toList();
            if (due.isEmpty) {
              break;
            }
            var projectId = due.first.project.id;
            done.add(projectId);
            await runOne(projectId, HostCiTrigger.allDue);
          }
        } else {
          var next = (await hostCi.getProjects()).next;
          if (next == null) {
            stdout.writeln('Nothing due');
          } else {
            await runOne(next.project.id, HostCiTrigger.next);
          }
        }
      } on HostCiQueueCancelledException {
        stderr.writeln('Cancelled while waiting');
        exitCode = 130;
      } finally {
        await sigint.cancel();
      }
      if (jsonOutput) {
        writeJson(runs.map(hostCiRunToJson).toList());
      } else if (runs.isNotEmpty) {
        stdout.writeln('# report: ${hostCi.report.indexPath}');
      }
      if (runs.any((run) => run.isRed)) {
        exitCode = 1;
      }
    });
    return true;
  }
}

class _CiFailuresCommand extends _CiSubCommand {
  _CiFailuresCommand()
    : super(
        name: 'failures',
        description:
            'The failure reports kept open (red and warnings, until validated '
            'or green), exit code 1 when one is red',
      );

  @override
  FutureOr<bool> onRun() async {
    await withHostCi((hostCi) async {
      var failures = (await hostCi.getProjects()).failures;
      if (jsonOutput) {
        writeJson([
          for (var status in failures)
            {
              'project': status.project.id,
              'runs': status.openFailures.map(hostCiRunToJson).toList(),
            },
        ]);
      } else if (failures.isEmpty) {
        stdout.writeln('No open failure report');
      } else {
        for (var status in failures) {
          var run = status.openFailure!;
          stdout.writeln(
            '${status.project.id} · ${hostCiRunStatusText(run)} · '
            '${_failureText(run)}'
            '${status.openFailures.length > 1 ? ' · ${status.openFailures.length} runs since ${hostCiTimeAgo(status.openFailures.first.startDateTime!)}' : ''}',
          );
        }
      }
      if (failures.any((status) => status.openFailure!.isRed)) {
        exitCode = 1;
      }
    });
    return true;
  }
}

class _CiValidateCommand extends _CiSubCommand {
  _CiValidateCommand()
    : super(
        name: 'validate',
        description:
            'Validate the open failure reports of a project (read and '
            'accepted): no longer kept open nor proposed while unchanged',
      ) {
    parser.addOption(_optionRun, help: 'Only this run');
  }

  @override
  FutureOr<bool> onRun() async {
    await withHostCi((hostCi) async {
      var project = await findProject(hostCi, singleArg('project'));
      var runId = int.tryParse(results.option(_optionRun) ?? '');
      var runs = await hostCi.validate(project.id, runId: runId);
      if (jsonOutput) {
        writeJson(runs.map((run) => run.id).toList());
      } else {
        stdout.writeln(
          runs.isEmpty
              ? 'No open report for ${project.id}'
              : 'Validated ${runs.map((run) => 'run ${run.id}').join(', ')} '
                    'of ${project.id}',
        );
      }
    });
    return true;
  }
}

class _CiContextCommand extends _CiSubCommand {
  _CiContextCommand()
    : super(
        name: 'context',
        description:
            'The Markdown report of a run (the last one of a project, or a '
            'run key), to paste to Claude: the context, every step with its '
            'command, the failure logs, the retry commands, the last runs',
        withJson: false,
      ) {
    parser.addFlag(
      _flagFull,
      help: 'Every log line of the failed steps (and the set up)',
      negatable: false,
    );
    parser.addOption(
      _optionMaxLines,
      help: 'Log lines kept per failed step',
      defaultsTo: '$hostCiMarkdownMaxLines',
    );
    parser.addFlag(
      _flagCopy,
      help: 'Copy to the clipboard (wl-copy, xclip or pbcopy) too',
      negatable: false,
    );
  }

  @override
  FutureOr<bool> onRun() async {
    await withHostCi((hostCi) async {
      var query = results.rest.isEmpty ? null : singleArg('project or run');
      DbHostCiRun? run;
      var runId = query == null ? null : int.tryParse(query);
      if (query == null) {
        run = await hostCi.getLatestRun();
      } else if (runId != null) {
        run = await hostCi.getRun(runId);
      } else {
        var project = await findProject(hostCi, query);
        run = await hostCi.getLastRun(project.id);
      }
      if (run == null) {
        throw StateError('No run${query == null ? '' : ' for $query'}');
      }
      var markdown = await hostCiRunMarkdown(
        hostCi,
        run,
        fullLog: results.flag(_flagFull),
        maxLines:
            int.tryParse(results.option(_optionMaxLines) ?? '') ??
            hostCiMarkdownMaxLines,
      );
      stdout.write(markdown);
      if (results.flag(_flagCopy)) {
        await _copyToClipboard(markdown);
      }
    });
    return true;
  }
}

/// Copy [text] to the clipboard with the first tool found.
Future<void> _copyToClipboard(String text) async {
  for (var command in [
    ['wl-copy'],
    ['xclip', '-selection', 'clipboard'],
    ['pbcopy'],
  ]) {
    var executable = whichSync(command.first);
    if (executable == null) {
      continue;
    }
    var process = await Process.start(executable, command.sublist(1));
    process.stdin.write(text);
    await process.stdin.close();
    // xclip stays alive to serve the selection: do not wait for it.
    unawaited(process.exitCode);
    stderr.writeln('# copied to the clipboard (${command.first})');
    return;
  }
  stderr.writeln('# no clipboard tool found (wl-copy, xclip, pbcopy)');
}

class _CiLogCommand extends _CiSubCommand {
  _CiLogCommand()
    : super(
        name: 'log',
        description:
            'The log of the last run of a project (or of a run key), one step '
            'only with --step (`failed` for the failed one)',
        withJson: false,
      ) {
    parser.addOption(_optionStep, help: 'Only this step (or `failed`)');
  }

  @override
  FutureOr<bool> onRun() async {
    await withHostCi((hostCi) async {
      var query = singleArg('project or run key');
      DbHostCiRun? run;
      var runId = int.tryParse(query);
      if (runId != null) {
        run = await hostCi.getRun(runId);
      } else {
        var project = await findProject(hostCi, query);
        run = await hostCi.getLastRun(project.id);
      }
      if (run == null) {
        throw StateError('No run for $query');
      }
      var lines = await hostCi.readLog(run);
      var stepOption = results.option(_optionStep);
      if (stepOption != null) {
        HostCiStepName? step;
        if (stepOption == 'failed') {
          step = run.failedStep?.stepName;
          if (step == null) {
            throw StateError('No failed step in run ${run.id}');
          }
        } else {
          step = hostCiStepNameParse(stepOption);
          if (step == null) {
            throw ArgumentError('Unknown step $stepOption');
          }
        }
        lines = [
          for (var section in hostCiLogSections(lines))
            if (section.step == step) ...section.lines,
        ];
      }
      for (var line in lines) {
        (line.isError ? stderr : stdout).writeln(line.text);
      }
      if (lines.isEmpty) {
        stderr.writeln(
          'No log (${run.log.v == null ? 'removed by the retention' : p.join(hostCi.logsDir, run.log.v!)})',
        );
      }
    });
    return true;
  }
}

class _CiReportCommand extends _CiSubCommand {
  _CiReportCommand()
    : super(
        name: 'report',
        description:
            'Write the web report (every page), print its path; --open opens '
            'it in the browser',
        withJson: false,
      ) {
    parser.addFlag(_flagOpen, help: 'Open in the browser', negatable: false);
  }

  @override
  FutureOr<bool> onRun() async {
    await withHostCi((hostCi) async {
      var index = await hostCi.report.writeAll();
      stdout.writeln(index);
      if (results.flag(_flagOpen)) {
        var opener = Platform.isMacOS
            ? 'open'
            : Platform.isWindows
            ? 'start'
            : 'xdg-open';
        await Process.start(opener, [index], mode: ProcessStartMode.detached);
      }
    });
    return true;
  }
}

class _CiQueueCommand extends _CiSubCommand {
  _CiQueueCommand()
    : super(
        name: 'queue',
        description: 'The run in progress and the runs waiting on this machine',
      );

  @override
  FutureOr<bool> onRun() async {
    await withHostCi((hostCi) async {
      var state = await hostCi.getQueue();
      if (jsonOutput) {
        writeJson({
          'running': state.running?.toJson(),
          'waiting': state.waiting.map((entry) => entry.toJson()).toList(),
        });
      } else if (state.isEmpty) {
        stdout.writeln('Nothing runs');
      } else {
        if (state.running != null) {
          stdout.writeln('running: ${state.running}');
        }
        for (var entry in state.waiting) {
          stdout.writeln('waiting: $entry');
        }
      }
    });
    return true;
  }
}

class _CiAddCommand extends _CiSubCommand {
  _CiAddCommand()
    : super(
        name: 'add',
        description:
            'Follow checkouts: paths, or ids under the git top '
            '(github.com/owner/repo, owner/repo); the current folder by '
            'default',
      );

  @override
  FutureOr<bool> onRun() async {
    await withHostCi((hostCi) async {
      var args = results.rest.isEmpty ? ['.'] : results.rest;
      var added = <DbHostCiProject>[];
      for (var arg in args) {
        added.add(await hostCi.addProject(await _resolvePath(arg)));
      }
      if (jsonOutput) {
        writeJson([
          for (var project in added) {'id': project.id, 'path': project.path.v},
        ]);
      } else {
        for (var project in added) {
          stdout.writeln('${project.id} (${project.path.v})');
        }
      }
    });
    return true;
  }

  Future<String> _resolvePath(String arg) async {
    if (Directory(arg).existsSync()) {
      return arg;
    }
    var gitTop = await tkPubFindGitTop();
    for (var candidate in [
      p.joinAll([gitTop, ...arg.split('/')]),
      p.joinAll([gitTop, 'github.com', ...arg.split('/')]),
    ]) {
      if (Directory(candidate).existsSync()) {
        return candidate;
      }
    }
    throw StateError('Checkout not found: $arg');
  }
}

class _CiRemoveCommand extends _CiSubCommand {
  _CiRemoveCommand()
    : super(
        name: 'remove',
        description: 'Stop following a project (its runs and logs deleted)',
        withJson: false,
      );

  @override
  FutureOr<bool> onRun() async {
    await withHostCi((hostCi) async {
      var project = await findProject(hostCi, singleArg('project'));
      var deleted = await hostCi.removeProject(project.id);
      if (deleted != null) {
        await hostCi.purgeDeletedProject(deleted);
      }
      stdout.writeln('Removed ${project.id}');
    });
    return true;
  }
}

class _CiSkipCommand extends _CiSubCommand {
  final bool skip;

  _CiSkipCommand({required this.skip})
    : super(
        name: skip ? 'skip' : 'unskip',
        description: skip
            ? 'Skip a project (never proposed nor run by next and all due), '
                  'or only a platform (--platform host or web: its test and '
                  'build steps)'
            : 'Undo skip (of the project or of a platform)',
        withJson: false,
      ) {
    parser.addOption(_optionPlatform, help: 'host or web');
  }

  @override
  FutureOr<bool> onRun() async {
    await withHostCi((hostCi) async {
      var project = await findProject(hostCi, singleArg('project'));
      var platformName = results.option(_optionPlatform);
      if (platformName == null) {
        await hostCi.setPaused(project.id, paused: skip);
        stdout.writeln('${project.id} ${skip ? 'skipped' : 'not skipped'}');
      } else {
        var platform = hostCiPlatformFromName(platformName);
        if (platform == null) {
          throw ArgumentError('Unknown platform $platformName');
        }
        var updated = await hostCi.setPlatformSkipped(
          project.id,
          platform,
          skipped: skip,
        );
        stdout.writeln(
          '${project.id} ${skip ? 'skips' : 'runs'} ${platform.name} test and build'
          ' (${updated.optionsSummary.isEmpty ? 'default options' : updated.optionsSummary})',
        );
      }
    });
    return true;
  }
}

class _CiPolicyCommand extends _CiSubCommand {
  _CiPolicyCommand()
    : super(
        name: 'policy',
        description:
            'What a failure of a step does: fail (red, the next steps '
            'skipped, the default), warn (--severity low, medium (default), '
            'high) or accept. Usage: policy <project> <step> <policy>',
        withJson: false,
      ) {
    parser.addOption(
      _optionSeverity,
      help: 'Severity of a warning',
      allowed: HostCiSeverity.values.map((value) => value.name),
    );
  }

  @override
  FutureOr<bool> onRun() async {
    await withHostCi((hostCi) async {
      var rest = results.rest;
      if (rest.length != 3) {
        throw ArgumentError(
          'Usage: dtk ci policy <project> <step> <fail|warn|accept>',
        );
      }
      var project = await findProject(hostCi, rest[0]);
      var steps = hostCiStepNamesParse(rest[1]);
      if (steps.isEmpty || steps.any((step) => step.policyStep == null)) {
        throw ArgumentError(
          'Step ${rest[1]}: test, build or one of '
          '${hostCiPolicySteps.map((step) => step == HostCiStepName.pubDowngrade ? 'downgrade' : step.label.replaceAll(' ', '-')).join(', ')}',
        );
      }
      var policy = HostCiFailurePolicy.values
          .where((value) => value.name == rest[2])
          .firstOrNull;
      if (policy == null) {
        throw ArgumentError('Policy ${rest[2]}: fail, warn or accept');
      }
      var severityName = results.option(_optionSeverity);
      var updated = project;
      for (var step in steps) {
        updated = await hostCi.setStepPolicy(
          project.id,
          step,
          policy,
          severity: severityName == null
              ? null
              : hostCiSeverityFromName(severityName),
        );
      }
      stdout.writeln(
        '${project.id}: ${updated.optionsSummary.isEmpty ? 'default options' : updated.optionsSummary}',
      );
    });
    return true;
  }
}

class _CiStepsCommand extends _CiSubCommand {
  _CiStepsCommand()
    : super(
        name: 'steps',
        description:
            'Show or set the steps of a project: steps <project> [<step>...] '
            '(analyze, format, test-host, test-web, build-web, build-host, '
            'test, build, downgrade), --all for every one, --pub-get-only to '
            'keep the lock files (no pub upgrade)',
        withJson: false,
      ) {
    parser.addFlag(_flagAll, help: 'Every step', negatable: false);
    parser.addFlag(
      _flagPubGetOnly,
      help: 'pub get instead of pub upgrade',
      defaultsTo: null,
    );
  }

  @override
  FutureOr<bool> onRun() async {
    await withHostCi((hostCi) async {
      var rest = results.rest;
      if (rest.isEmpty) {
        throw ArgumentError('Usage: dtk ci steps <project> [<step>...]');
      }
      var project = await findProject(hostCi, rest.first);
      var stepArgs = rest.sublist(1);
      var all = results.flag(_flagAll);
      var pubGetOnly = results.wasParsed(_flagPubGetOnly)
          ? results.flag(_flagPubGetOnly)
          : null;
      if (stepArgs.isNotEmpty || all || pubGetOnly != null) {
        List<HostCiStepName>? steps;
        if (all) {
          steps = null;
        } else if (stepArgs.isNotEmpty) {
          steps = [];
          for (var arg in stepArgs) {
            var parsed = hostCiStepNamesParse(arg);
            if (parsed.isEmpty ||
                parsed.any((step) => !hostCiSelectableSteps.contains(step))) {
              throw ArgumentError(
                'Step $arg: analyze, format, test-host, test-web, build-web, '
                'build-host, test, build or downgrade',
              );
            }
            steps.addAll(parsed);
          }
        } else {
          steps = project.selectedSteps;
        }
        await hostCi.setProjectOptions(
          project.id,
          steps: steps,
          extraArgs: project.extraArgs.v,
          pubGetOnly: pubGetOnly,
        );
        project = (await hostCi.store.getProject(project.id))!;
      }
      stdout.writeln(
        '${project.id}: ${project.enabledSteps.map((step) => step.label).join(' → ')}',
      );
    });
    return true;
  }
}
