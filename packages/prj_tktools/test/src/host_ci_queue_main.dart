import 'dart:io';

import 'package:tekartik_prj_tktools/host_ci.dart';

/// Takes the Host CI run slot of a folder, run as a sub process by the
/// tests: `host_ci_queue_main.dart <dir> <name> [<release file>]`; prints
/// `<name> acquired` once it has the slot, releases it once the release file
/// exists (at once without it).
Future<void> main(List<String> arguments) async {
  var dir = arguments[0];
  var name = arguments[1];
  var releaseFile = arguments.length > 2 ? File(arguments[2]) : null;
  var queue = HostCiRunQueue(
    dir,
    pollInterval: const Duration(milliseconds: 50),
  );
  var slot = await queue.acquire(
    HostCiQueueEntry(
      pid: pid,
      project: name,
      trigger: 'manual',
      client: 'test',
      time: DateTime.now(),
    ),
  );
  stdout.writeln('$name acquired');
  await stdout.flush();
  while (releaseFile != null && !releaseFile.existsSync()) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await slot.release();
  stdout.writeln('$name released');
  await stdout.flush();
}
