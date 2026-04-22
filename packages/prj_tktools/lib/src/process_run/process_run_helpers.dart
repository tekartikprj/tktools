import 'package:process_run/shell.dart';

/// Allow parsing a list of command in a single (typically result.rest when
/// using args package.

/// [separator] defaults to ';'
Iterable<ShellCommand> shellArgsToCommandList(
  List<String> args, {
  String? separator,
}) sync* {
  if (args.isEmpty) {
    return;
  }
  if (args.length == 1) {
    args = shellScriptLineToArguments(args.first);
  }
  var current = <String>[];

  ShellCommand processExecutableArguments() {
    return ShellCommand.fromArguments(current);
  }

  separator ??= ';';

  for (var i = 0; i < args.length; i++) {
    var arg = args[i];
    if (arg == separator) {
      if (current.isNotEmpty) {
        yield processExecutableArguments();
        current.clear();
      }
    } else {
      current.add(arg);
    }
  }
  if (current.isNotEmpty) {
    yield processExecutableArguments();
  }
}
