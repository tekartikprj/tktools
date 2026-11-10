import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:process_run/shell.dart'
    show Shell, ShellEnvironment, ShellLinesController, ShellProcesses;

/// The encoding of the output of a process: UTF-8, a malformed sequence
/// replaced instead of failing the run (or losing its line).
const _outputEncoding = Utf8Codec(allowMalformed: true);

/// A started process, its output as lines.
abstract class HostCiProcess {
  /// Process id, 0 for a fake.
  int get pid;

  /// stdout, line by line.
  Stream<String> get stdoutLines;

  /// stderr, line by line.
  Stream<String> get stderrLines;

  /// The exit code, once exited (negative when killed by a signal).
  Future<int> get exitCode;

  /// Kill the process and its descendants (sigterm, [force] for sigkill).
  ///
  /// Returns true when the process was still running (the signals are sent
  /// right after, once its descendants are known).
  bool kill({bool force = false});
}

/// Starts the processes of a run, replaced by a fake in the tests.
abstract class HostCiProcessStarter {
  /// Start [executable] with [arguments] in [workingDirectory].
  ///
  /// Throws when the process cannot start (executable not found).
  Future<HostCiProcess> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  });

  /// The Flutter version, null when flutter is not found.
  Future<String?> readFlutterVersion();
}

/// Starts real processes, each one the command of a process_run [Shell] of
/// its own (its output through two [ShellLinesController]).
///
/// The executable is resolved through process_run's shell environment (the
/// user `env.yaml` paths: nvm's node, flutter, Android tools). Killing a
/// process kills its whole tree (`ShellProcesses`, by parent pid): `flutter
/// test` spawns `dart test`, which spawns chrome or node. Not `Shell.kill`:
/// it ends the run of the shell at once, where a run waits for the exit code
/// of the process killed and for the end of its output.
///
/// Where `setsid` is found (Linux, not macOS), the process gets its own
/// session and process group: away from the terminal of `dtk ci` (ctrl-c
/// does not reach it, a password prompt fails instead of waiting) and its
/// group is killed too (an orphan of the tree, its parent gone, is still in
/// it).
class HostCiIoProcessStarter implements HostCiProcessStarter {
  /// The environment the processes run in, process_run's by default.
  final ShellEnvironment environment;

  /// Creates the starter.
  HostCiIoProcessStarter({ShellEnvironment? environment})
    : environment = environment ?? ShellEnvironment();

  /// True when `setsid` is used (Linux and macOS, when found).
  bool get _useProcessGroup => Platform.isLinux || Platform.isMacOS;

  @override
  Future<HostCiProcess> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    var resolved = environment.whichSync(executable);
    if (resolved == null) {
      throw ProcessException(
        executable,
        arguments,
        '$executable not found in the path',
      );
    }
    var setsid = _useProcessGroup ? environment.whichSync('setsid') : null;
    var out = ShellLinesController(encoding: _outputEncoding);
    var err = ShellLinesController(encoding: _outputEncoding);
    var shell = Shell(
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: false,
      stdoutEncoding: _outputEncoding,
      stderrEncoding: _outputEncoding,
      stdout: out.sink,
      stderr: err.sink,
      verbose: false,
      throwOnError: false,
    );
    var started = Completer<Process>();
    // Not awaited: the run ends once the process exited and its output was
    // read to its end (the pipes closed: a descendant may hold them longer),
    // the lines end then.
    unawaited(
      shell
          .runExecutableArguments(setsid ?? resolved, [
            if (setsid != null) resolved,
            ...arguments,
          ], onProcess: (process) => started.complete(process))
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              // It could not start (the working directory is missing).
              if (!started.isCompleted) {
                started.completeError(error, stackTrace);
              }
            },
          )
          .whenComplete(() {
            out.close();
            err.close();
          }),
    );
    return _ShellProcess(
      await started.future,
      processGroup: setsid != null,
      out: out,
      err: err,
    );
  }

  @override
  Future<String?> readFlutterVersion() async {
    try {
      var flutter = environment.whichSync('flutter');
      if (flutter == null) {
        return null;
      }
      // <flutterRoot>/bin/flutter, the version file is at the root.
      var versionFile = File(p.join(p.dirname(p.dirname(flutter)), 'version'));
      if (versionFile.existsSync()) {
        return versionFile.readAsStringSync().trim();
      }
    } catch (_) {
      // Not worth failing a run for.
    }
    return null;
  }
}

/// The command of a [Shell], running.
class _ShellProcess implements HostCiProcess {
  /// The process, as the shell gives it when it starts (`onProcess`).
  final Process process;

  /// True when the process is the leader of its own process group.
  final bool processGroup;

  /// The output of the shell, closed at the end of its run.
  final ShellLinesController out;

  /// The errors of the shell, closed at the end of its run.
  final ShellLinesController err;

  /// True once exited.
  var _exited = false;

  _ShellProcess(
    this.process, {
    required this.processGroup,
    required this.out,
    required this.err,
  }) {
    unawaited(
      process.exitCode.then((_) {
        _exited = true;
      }),
    );
  }

  @override
  int get pid => process.pid;

  @override
  Stream<String> get stdoutLines => out.stream;

  @override
  Stream<String> get stderrLines => err.stream;

  /// The one of the process, not of the run of the shell: that one comes
  /// with the end of the output, which a descendant left behind holds.
  @override
  Future<int> get exitCode => process.exitCode;

  @override
  bool kill({bool force = false}) {
    if (_exited) {
      return false;
    }
    var signal = force ? ProcessSignal.sigkill : ProcessSignal.sigterm;
    unawaited(_killTree(signal));
    return true;
  }

  /// Sends [signal] to the process, its descendants (read before any signal:
  /// an orphan gets another parent) and its process group; sigkill after 5
  /// seconds for the ones still running.
  Future<void> _killTree(ProcessSignal signal) async {
    var descendants = await ShellProcesses.descendantsOf(process.pid);
    if (processGroup) {
      try {
        // A negative pid: the whole process group.
        Process.killPid(-process.pid, signal);
      } catch (_) {
        // Gone already.
      }
    }
    await ShellProcesses.kill([process.pid, ...descendants], signal: signal);
  }
}

/// A scripted process, for the tests.
class HostCiFakeProcess implements HostCiProcess {
  final _stdout = StreamController<String>();
  final _stderr = StreamController<String>();
  final _exitCode = Completer<int>();

  /// How many times [kill] was called.
  var killCount = 0;

  /// Creates a fake process, [out] and [err] lines are written at once, the
  /// process exits with [exitCode] unless it is null (it then runs until
  /// [exit] or [kill]).
  HostCiFakeProcess({
    List<String> out = const [],
    List<String> err = const [],
    int? exitCode,
  }) {
    for (var line in out) {
      _stdout.add(line);
    }
    for (var line in err) {
      _stderr.add(line);
    }
    if (exitCode != null) {
      exit(exitCode);
    }
  }

  /// Write a line on stdout.
  void writeOut(String line) => _stdout.add(line);

  /// Write a line on stderr.
  void writeErr(String line) => _stderr.add(line);

  /// Exit with [code].
  void exit(int code) {
    if (_exitCode.isCompleted) {
      return;
    }
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    _exitCode.complete(code);
  }

  @override
  int get pid => 0;

  @override
  Stream<String> get stdoutLines => _stdout.stream;

  @override
  Stream<String> get stderrLines => _stderr.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  bool kill({bool force = false}) {
    killCount++;
    exit(-15);
    return true;
  }
}

/// A started fake process, with what was asked.
class HostCiFakeProcessStart {
  /// The executable.
  final String executable;

  /// The arguments.
  final List<String> arguments;

  /// The working directory.
  final String workingDirectory;

  /// The process.
  final HostCiFakeProcess process;

  /// Creates a start record.
  HostCiFakeProcessStart({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.process,
  });

  /// The command line.
  String get commandLine => [executable, ...arguments].join(' ');

  @override
  String toString() => commandLine;
}

/// Starts fake processes, scripted by [onStart], for the tests.
class HostCiFakeProcessStarter implements HostCiProcessStarter {
  /// Builds the process of a command, the default exits 0 at once.
  final HostCiFakeProcess Function(String executable, List<String> arguments)?
  onStart;

  /// The Flutter version reported.
  final String? flutterVersion;

  /// Every process started, in order.
  final starts = <HostCiFakeProcessStart>[];

  /// Creates the starter.
  HostCiFakeProcessStarter({this.onStart, this.flutterVersion});

  @override
  Future<HostCiProcess> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    var process =
        onStart?.call(executable, arguments) ?? HostCiFakeProcess(exitCode: 0);
    starts.add(
      HostCiFakeProcessStart(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        process: process,
      ),
    );
    return process;
  }

  @override
  Future<String?> readFlutterVersion() async => flutterVersion;
}
