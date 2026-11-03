@TestOn('vm')
library;

import 'dart:io';

import 'package:process_run/shell.dart' show ShellProcesses, whichSync;
import 'package:tekartik_prj_tktools/host_ci.dart';
import 'package:test/test.dart';

void main() {
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
