import 'package:dev_build/shell.dart';
import 'package:http/http.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';

/// A shell that can run sudo commands by providing the password via stdin
class SudoShell {
  /// The sudo password
  final String password;

  /// Create a SudoShell with the given password
  SudoShell({required this.password});

  /// Run the given script with sudo
  Future<List<ProcessResult>> run(String script, {bool? interactive}) async {
    interactive ??= false;
    var passwordBytes = systemEncoding.encode(password);

    /// Use sudo --stdin to read the password from stdin
    /// Use an alias for simplicity (only need to refer to sudo instead of sudo --stdin
    var env = ShellEnvironment()..aliases['sudo'] = 'sudo --stdin';
    Shell shell;
    StreamController<List<int>>? controller;
    if (interactive) {
      controller = StreamController<List<int>>();
      sharedStdIn.listen((data) {
        controller!.add(data);
      });
      shell = Shell(stdin: controller.stream, environment: env);
    } else {
      // Create a fake stdin stream from the password variable
      var stdin = ByteStream.fromBytes(passwordBytes).asBroadcastStream();
      shell = Shell(stdin: stdin, environment: env);
    }

    try {
      return await shell.run('sudo $script');
    } finally {
      await controller?.close();
    }
  }
}
