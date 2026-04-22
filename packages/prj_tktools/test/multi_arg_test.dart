import 'package:dev_build/shell.dart';
import 'package:tekartik_prj_tktools/src/process_run/process_run_helpers.dart';
import 'package:test/test.dart';

Future<void> main() async {
  test('shellArgsToCommandList', () {
    expect(
      shellArgsToCommandList([
        'dart',
        'pub',
        'get',
        ';',
        'dart',
        'test',
        'test/min_test.dart',
      ]),
      [
        ShellCommand('dart', ['pub', 'get']),
        ShellCommand('dart', ['test', 'test/min_test.dart']),
      ],
    );
    expect(
      shellArgsToCommandList(
        stringToArguments('dart pub get ; dart test test/min_test.dart'),
      ),
      [
        ShellCommand('dart', ['pub', 'get']),
        ShellCommand('dart', ['test', 'test/min_test.dart']),
      ],
    );
  });
}
