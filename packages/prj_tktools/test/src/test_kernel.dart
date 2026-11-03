import 'dart:io';

import 'package:path/path.dart';

/// [script] compiled once into a kernel file in [dir] (`dart compile
/// kernel`), the program the tests run as a sub process: it starts in a
/// fraction of a second instead of compiling the script again at each start
/// (seconds each on a busy CI runner). The script itself when the
/// compilation fails.
Future<String> compileTestScript(String script, String dir) async {
  var kernel = join(dir, '${basenameWithoutExtension(script)}.dill');
  var result = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'kernel',
    script,
    '-o',
    kernel,
  ]);
  if (result.exitCode == 0 && File(kernel).existsSync()) {
    return kernel;
  }
  stderr.writeln('$script not compiled, run as is: ${result.stderr}');
  return script;
}
