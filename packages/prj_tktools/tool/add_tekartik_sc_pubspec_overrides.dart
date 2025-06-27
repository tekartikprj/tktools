import 'package:process_run/process_run.dart';

Future<void> main() async {
  shellEnvironment = ShellEnvironment()
    ..aliases['tkpub'] = 'dart run example/tkpub.dart';
  await run('tkpub add --pubspec-overrides tekartik_sc');
}
