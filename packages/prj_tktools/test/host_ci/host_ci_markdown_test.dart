import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';
import 'package:tekartik_prj_tktools/host_ci.dart';
import 'package:test/test.dart';

void main() {
  initCvHostCi();
  DbHostCiStep step(
    HostCiStepName name,
    HostCiStepStatus status, {
    int? exitCode,
    String? package,
    String? command,
  }) => DbHostCiStep()
    ..name.v = name.name
    ..status.v = status.name
    ..exitCode.v = exitCode
    ..duration.v = 1000
    ..failedPackage.v = package
    ..failedCommand.v = command;

  List<HostCiOutputLine> log(List<String> texts) => [
    for (var text in texts)
      if (text.startsWith('! '))
        HostCiOutputLine(text.substring(2), isError: true)
      else
        HostCiOutputLine(text),
  ];

  var project = hostCiProjectStore.record('github.com/owner/repo').cv()
    ..path.v = '/git/github.com/owner/repo'
    ..name.v = 'repo';

  DbHostCiRun newRun(
    int id,
    List<DbHostCiStep> steps,
    HostCiRunStatus status,
  ) => hostCiRunStore.record(id).cv()
    ..project.v = project.id
    ..path.v = project.path.v
    ..trigger.v = 'manual'
    ..status.v = status.name
    ..start.v = DateTime(2026, 11, 3, 10).millisecondsSinceEpoch
    ..end.v = DateTime(2026, 11, 3, 10, 2).millisecondsSinceEpoch
    ..head.v = 'a' * 40
    ..dirty.v = 0
    ..runCiVersion.v = '1.1.17'
    ..steps.v = steps;

  test('a red analyze: the steps, the failing package log, the retry', () {
    var run = newRun(3, [
      step(HostCiStepName.pubUpgrade, HostCiStepStatus.success, exitCode: 0),
      step(
        HostCiStepName.analyze,
        HostCiStepStatus.failure,
        exitCode: 255,
        package: './app',
        command: 'flutter analyze --no-pub .',
      ),
      step(HostCiStepName.format, HostCiStepStatus.skipped),
    ], HostCiRunStatus.failure);
    var markdown = hostCiRunMarkdownText(
      run,
      project: project,
      runs: [run],
      lines: log([
        '# host ci run 3',
        '=== pub upgrade (1/3) ===',
        r'$ dart pub global run dev_build:run_ci --pub-upgrade --recursive',
        '=== analyze (2/3) ===',
        r'$ dart pub global run dev_build:run_ci --analyze --no-pub-get --recursive',
        '# package: ./lib_ok',
        r'$ dart analyze .',
        'No issues found!',
        '# package: ./app',
        r'$ flutter analyze --no-pub .',
        '   info • something is deprecated • lib/main.dart:1:1',
        '! ERROR ShellException(flutter analyze --no-pub ., exitCode 1, workingDirectory: ./app) in ./app',
        '# package: ./other',
        r'$ dart analyze .',
        'No issues found!',
        '! run_ci failed ShellException(flutter analyze --no-pub ., exitCode 1)',
      ]),
      now: DateTime(2026, 11, 3, 11),
    );
    expect(
      markdown,
      startsWith('# Host CI run 3: github.com/owner/repo, red\n'),
    );
    expect(markdown, contains('- Report: open (1 red or warning run since'));
    expect(
      markdown,
      contains(
        '| 2 | analyze | failure | 0:01 | 255 | ./app | '
        '`dart pub global run dev_build:run_ci --analyze --no-pub-get '
        '--recursive` |',
      ),
    );
    expect(markdown, contains('| 3 | format | skipped |'));
    expect(markdown, contains('### analyze: failure, exit code 255'));
    // The failing package, not the green ones, and the run_ci summary.
    expect(markdown, contains('lib/main.dart:1:1'));
    expect(markdown, isNot(contains('# package: ./lib_ok')));
    expect(markdown, contains('! run_ci failed ShellException'));
    expect(
      markdown,
      contains('`dtk ci run github.com/owner/repo --from analyze`'),
    );
  });

  test('a long test log: the failing tests first', () {
    var run = newRun(4, [
      step(
        HostCiStepName.testHost,
        HostCiStepStatus.failure,
        exitCode: 1,
        package: '.',
        command: 'dart test',
      ),
    ], HostCiRunStatus.failure);
    var markdown = hostCiRunMarkdownText(
      run,
      project: project,
      runs: [run],
      lines: log([
        '=== test host (1/1) ===',
        '# package: .',
        for (var i = 0; i < 300; i++) '00:0$i +$i: test/a_test.dart: ok $i',
        '00:05 +300 -1: test/a_test.dart: first [E]',
        '  Expected: <200>',
        '    Actual: <404>',
        '00:05 +300 -2: test/a_test.dart: second [E]',
        '  Expected: <200>',
        '    Actual: <404>',
        '00:06 +300 -2: Some tests failed.',
        // The output written again by run_ci on failure: not new failures.
        '! ERROR ShellException(dart test, exitCode 1, workingDirectory: .)',
        '! out: 00:00 +0: loading test/a_test.dart',
        '! 00:05 +300 -1: test/a_test.dart: first [E]',
        '!   Expected: <200>',
        '!     Actual: <404>',
        '! 00:05 +300 -2: test/a_test.dart: second [E]',
        '!   Expected: <200>',
        '!     Actual: <404>',
        '! 00:06 +300 -2: Some tests failed.',
      ]),
      now: DateTime(2026, 11, 3, 11),
      maxLines: 50,
    );
    expect(markdown, contains('Failing tests (2, in the order they failed):'));
    // The run_ci echo: not listed again, its errors not written again.
    expect(
      markdown,
      contains(
        '- test/a_test.dart: first\n- test/a_test.dart: second\n\nTheir errors',
      ),
    );
    var errors = markdown.substring(
      markdown.indexOf('Their errors'),
      markdown.indexOf('End of the log'),
    );
    expect(RegExp(r'second \[E\]').allMatches(errors), hasLength(1));
    expect(markdown, contains('- test/a_test.dart: first\n'));
    expect(
      markdown,
      contains('00:05 +300 -1: test/a_test.dart: first [E]\n  Expected:'),
    );
    expect(markdown, contains('(same error as "test/a_test.dart: first")'));
    expect(markdown, contains('00:06 +300 -2: Some tests failed.'));
    expect(markdown, isNot(contains('ok 100')));
    expect(
      markdown,
      contains('`dtk ci run github.com/owner/repo --from test-host`'),
    );
  });
}
