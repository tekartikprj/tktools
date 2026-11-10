@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:process_run/shell.dart' show ShellProcesses, whichSync;
import 'package:tekartik_prj_tktools/host_ci.dart';
import 'package:test/test.dart';

void main() {
  group('output and start', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('host_ci_process_test');
    });
    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('output: the lines of stdout and stderr, the exit code', () async {
      // The last line has no end, \377 is not UTF-8.
      var process = await HostCiIoProcessStarter().start('sh', [
        '-c',
        r"printf 'one\n\ntwo \303\251\nbad \377\nlast'; echo oops >&2; exit 3",
      ], workingDirectory: dir.path);
      expect(process.pid, greaterThan(0));
      var out = process.stdoutLines.toList();
      var err = process.stderrLines.toList();
      expect(await process.exitCode, 3);
      expect(await out, ['one', '', 'two é', 'bad \u{FFFD}', 'last']);
      expect(await err, ['oops']);
      expect(process.kill(), isFalse);
    }, testOn: '!windows');

    test('exit code: not held by a child keeping the output open', () async {
      var process = await HostCiIoProcessStarter().start('sh', [
        '-c',
        'sleep 3 & echo started; exit 4',
      ], workingDirectory: dir.path);
      var lines = <String>[];
      var outDone = process.stdoutLines.listen(lines.add).asFuture<void>();
      var stopwatch = Stopwatch()..start();
      expect(await process.exitCode, 4);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      // The lines end with the child (it holds the pipe).
      await outDone;
      expect(lines, ['started']);
    }, testOn: '!windows');

    test('start: unknown executable, missing working directory', () async {
      var starter = HostCiIoProcessStarter();
      await expectLater(
        starter.start(
          'host_ci_no_such_executable',
          [],
          workingDirectory: dir.path,
        ),
        throwsA(isA<ProcessException>()),
      );
      await expectLater(
        starter.start('dart', [
          '--version',
        ], workingDirectory: p.join(dir.path, 'none')),
        throwsA(anything),
      );
    });
  });

  test('kill: the process and its descendants', () async {
    var dir = await Directory.systemTemp.createTemp('host_ci_process_test');
    try {
      // A child out of the process group (setsid) is only found through the
      // tree (macOS has no setsid: a plain child).
      var setsid = whichSync('setsid') == null ? '' : 'setsid ';
      var process = await HostCiIoProcessStarter().start('sh', [
        '-c',
        '${setsid}sleep 31 & sleep 30',
      ], workingDirectory: dir.path);
      var descendants = <int>[];
      for (var i = 0; i < 100 && descendants.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        descendants = await ShellProcesses.descendantsOf(process.pid);
      }
      expect(descendants, isNotEmpty);
      expect(process.kill(), isTrue);
      expect(await process.exitCode, isNot(0));
      for (var i = 0; i < 60; i++) {
        var running = [
          for (var pid in descendants)
            if (await ShellProcesses.isRunning(pid)) pid,
        ];
        if (running.isEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      for (var pid in descendants) {
        expect(await ShellProcesses.isRunning(pid), isFalse);
      }
      // Exited: nothing to kill.
      expect(process.kill(), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  }, testOn: '!windows');
}
