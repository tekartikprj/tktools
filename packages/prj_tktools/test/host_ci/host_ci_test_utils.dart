import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tekartik_prj_tktools/host_ci.dart';

/// A temporary folder, deleted at the end of the test (call `addTearDown`
/// with [deleteDir]).
Directory newTempDir(String prefix) =>
    Directory.systemTemp.createTempSync('host_ci_$prefix');

/// Delete [dir], ignoring errors.
void deleteDir(Directory dir) {
  try {
    dir.deleteSync(recursive: true);
  } catch (_) {}
}

/// Run git in [path], throws on a non zero exit code.
Future<String> git(String path, List<String> args) async {
  var result = await Process.run('git', [
    '-c',
    'user.name=Test',
    '-c',
    'user.email=test@example.com',
    '-c',
    'commit.gpgsign=false',
    ...args,
  ], workingDirectory: path);
  if (result.exitCode != 0) {
    throw StateError('git $args failed: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

/// Create a git repository at [path] with one commit, an `origin` remote when
/// [remote] is given, a flutter app in `flutter_app` when [flutterApp] is
/// true (one host build).
Future<void> createGitRepo(
  String path, {
  String? remote,
  bool flutterApp = false,
}) async {
  Directory(path).createSync(recursive: true);
  await git(path, ['init', '-q', '-b', 'main']);
  File(p.join(path, 'README.md')).writeAsStringSync('# test\n');
  if (flutterApp) {
    createFlutterApp(p.join(path, 'flutter_app'));
  }
  await git(path, ['add', '.']);
  await git(path, ['commit', '-q', '-m', 'first']);
  if (remote != null) {
    await git(path, ['remote', 'add', 'origin', remote]);
  }
}

/// A flutter app at [path] that Host CI builds for the host: a pubspec
/// depending on flutter, `lib/main.dart` and the platform folders (a
/// `.gitkeep` in each), [platforms] all of them by default.
void createFlutterApp(
  String path, {
  List<String> platforms = hostCiHostBuildPlatforms,
  bool main = true,
  bool flutter = true,
}) {
  Directory(path).createSync(recursive: true);
  File(p.join(path, 'pubspec.yaml')).writeAsStringSync(
    'name: ${p.basename(path)}\n'
    'environment:\n'
    '  sdk: ^3.12.0\n'
    '${flutter ? 'dependencies:\n  flutter:\n    sdk: flutter\n' : ''}',
  );
  if (main) {
    File(p.join(path, 'lib', 'main.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}\n');
  }
  for (var platform in platforms) {
    File(p.join(path, platform, '.gitkeep')).createSync(recursive: true);
  }
}

/// Add a commit to the repository at [path].
Future<String> commit(String path, String message) async {
  File(
    p.join(path, 'README.md'),
  ).writeAsStringSync('# $message\n', mode: FileMode.append);
  await git(path, ['add', '.']);
  await git(path, ['commit', '-q', '-m', message]);
  return await git(path, ['rev-parse', 'HEAD']);
}

/// The step of a `dart pub global run dev_build:run_ci ...` command (or of a
/// host build `flutter build <host> --no-pub`), null for another command.
HostCiStepName? stepOfArguments(List<String> arguments) {
  if (hostCiStepOfArguments(arguments) == HostCiStepName.buildHost) {
    return HostCiStepName.buildHost;
  }
  var index = arguments.indexOf(hostCiRunCiPackage);
  if (index < 0) {
    return null;
  }
  var rest = arguments.sublist(index + 1);
  for (var step in HostCiStepName.values) {
    var stepArgs = step.runCiArguments;
    if (rest.length >= stepArgs.length + 1 &&
        _listEquals(rest.sublist(0, stepArgs.length), stepArgs) &&
        rest[stepArgs.length] == '--recursive') {
      return step;
    }
  }
  return null;
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// A fake starter scripting the tool versions and one process per step.
///
/// [steps] gives the process (exit code, output) per step, success and a
/// little output by default. `--version` commands succeed unless
/// [runCiFound] or [dartFound] is false. [onStep] is called when a step
/// starts (before its process).
HostCiFakeProcessStarter fakeStarter({
  Map<HostCiStepName, HostCiFakeProcess Function()> steps = const {},
  String runCiVersion = '1.1.17',
  bool runCiFound = true,
  bool dartFound = true,
  void Function(HostCiStepName step)? onStep,
}) {
  return HostCiFakeProcessStarter(
    flutterVersion: '3.47.8',
    onStart: (executable, arguments) {
      if (arguments.contains('--version')) {
        if (arguments.first == '--version') {
          return dartFound
              ? HostCiFakeProcess(
                  out: ['Dart SDK version: 3.13.7 (stable) (Mon Oct 20)'],
                  exitCode: 0,
                )
              : HostCiFakeProcess(err: ['not found'], exitCode: 127);
        }
        return runCiFound
            ? HostCiFakeProcess(out: [runCiVersion], exitCode: 0)
            : HostCiFakeProcess(
                err: ['Could not find package `dev_build`'],
                exitCode: 65,
              );
      }
      var step = stepOfArguments(arguments);
      if (step != null) {
        onStep?.call(step);
        return steps[step]?.call() ??
            HostCiFakeProcess(
              out: ['# package: .', r'$ dart ' + step.label, 'ok'],
              exitCode: 0,
            );
      }
      return HostCiFakeProcess(exitCode: 0);
    },
  );
}

/// The steps of the processes started, in order (`--version` ones
/// excluded).
List<HostCiStepName> startedSteps(HostCiFakeProcessStarter starter) => [
  for (var start in starter.starts) ?stepOfArguments(start.arguments),
];

/// A failing step process: `run_ci` reporting [package] and [command].
HostCiFakeProcess failingStep({
  String package = './app',
  String command = 'dart analyze',
  int exitCode = 1,
}) {
  var error =
      'ERROR ShellException($command, exitCode $exitCode, '
      'workingDirectory: $package) in $package';
  return HostCiFakeProcess(
    out: ['# package: $package', '\$ $command'],
    err: [error],
    exitCode: exitCode,
  );
}

/// The default steps of a run, in order.
const defaultSteps = [
  HostCiStepName.pubUpgrade,
  HostCiStepName.analyze,
  HostCiStepName.format,
  HostCiStepName.testHost,
  HostCiStepName.testWeb,
  HostCiStepName.buildWeb,
  HostCiStepName.buildHost,
  HostCiStepName.pubDowngrade,
  HostCiStepName.analyzeDowngrade,
  HostCiStepName.pubRestore,
];

/// Open Host CI in a temporary [dir] (the io database there), fast queue
/// polling, the report written unless [writeReport] is false.
Future<HostCi> openTestHostCi(
  String dir, {
  HostCiProcessStarter? starter,
  bool writeReport = false,
  DateTime Function()? now,
}) => HostCi.open(
  dir: dir,
  starter: starter,
  client: 'test',
  pollInterval: const Duration(milliseconds: 50),
  writeReport: writeReport,
  now: now,
);
