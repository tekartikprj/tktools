import 'dart:io';

import 'package:process_run/shell.dart';

/// Runs [executable] with [arguments]: its result whatever its exit code,
/// nothing shown, no input (its end at once, as `Process.run` does).
/// [environment] is added to the current one.
Future<ProcessResult> testRun(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => Shell(
  workingDirectory: workingDirectory,
  environment: environment,
  stdin: const Stream<List<int>>.empty(),
  verbose: false,
  throwOnError: false,
).runExecutableArguments(executable, arguments);

/// Runs `dart` (the running one) with [arguments], see [testRun].
Future<ProcessResult> testRunDart(
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => testRun(
  Platform.resolvedExecutable,
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
);
