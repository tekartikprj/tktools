@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `dtk run` and `dtk test` command line tests, run as a sub process in a
/// fixture project (a fake Flutter SDK in its package config), no device
/// needed (`--dry-run`), a real `dart run` in a project without dependency.
void main() {
  late Directory topDir;
  late String app;
  late String hello;
  late String cliScript;

  void write(String path, String content) {
    File(p.join(topDir.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  Future<ProcessResult> dtk(
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) => Process.run(
    Platform.resolvedExecutable,
    [cliScript, ...arguments],
    workingDirectory: workingDirectory ?? app,
    environment: environment,
  );

  /// The stdout of a successful dtk call.
  Future<String> dtkOut(
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    var result = await dtk(arguments, environment: environment);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return result.stdout as String;
  }

  setUpAll(() async {
    topDir = Directory.systemTemp.createTempSync('dtk_run');
    app = p.join(topDir.path, 'app');
    hello = p.join(topDir.path, 'hello');
    Map<String, Object?> package(String name, String root) => {
      'name': name,
      'rootUri': '../../$root',
      'packageUri': 'lib/',
    };
    write('sdk/packages/flutter/lib/widgets.dart', '');
    write(
      'sdk/packages/flutter_test/lib/flutter_test.dart',
      "export 'package:flutter/widgets.dart';",
    );
    write(
      'deps/dep_flutter/lib/dep_flutter.dart',
      "import 'package:flutter/widgets.dart';",
    );
    write('app/pubspec.yaml', 'name: app\n');
    write(
      'app/.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          package('app', 'app'),
          package('flutter', 'sdk/packages/flutter'),
          package('flutter_test', 'sdk/packages/flutter_test'),
          package('dep_flutter', 'deps/dep_flutter'),
        ],
      }),
    );
    write(
      'app/lib/main.dart',
      "import 'package:dep_flutter/dep_flutter.dart';\nvoid main() {}",
    );
    write('app/lib/main_cli.dart', 'void main() {}');
    write('app/tool/hello.dart', 'void main() {}');
    write('app/test/a_test.dart', "import 'package:test/test.dart';");
    write(
      'app/test/src/w_test.dart',
      "import 'package:flutter_test/flutter_test.dart';",
    );
    // A real project, no dependency.
    write('hello/pubspec.yaml', 'name: hello\nenvironment:\n  sdk: ^3.0.0\n');
    write(
      'hello/tool/hello.dart',
      "void main(List<String> args) => print('hello \${args.join(',')}');",
    );
    write('hello/tool/fail.dart', "import 'dart:io';\nvoid main() => exit(3);");
    var pubGet = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'get',
      '--offline',
    ], workingDirectory: hello);
    expect(pubGet.exitCode, 0, reason: '${pubGet.stderr}');
    // Compiled once: a sub process per command.
    cliScript = p.join(topDir.path, 'dtk.dill');
    var compile = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'kernel',
      p.join('test', 'src', 'dtk_cli_main.dart'),
      '-o',
      cliScript,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stderr}');
  });

  tearDownAll(() {
    topDir.deleteSync(recursive: true);
  });

  test('run --list', () async {
    var lines = LineSplitter.split(
      await dtkOut(['run', '--list']),
    ).map((line) => line.split(RegExp(r'\s+')).join(' ')).toList();
    var testChain =
        'test/src/w_test.dart -> package:flutter_test/flutter_test.dart';
    var mainChain =
        'lib/main.dart -> package:dep_flutter/dep_flutter.dart -> '
        'package:flutter/widgets.dart';
    expect(lines, [
      'lib/main.dart flutter $mainChain',
      'lib/main_cli.dart dart',
      'tool/hello.dart dart',
      'test/ flutter $testChain',
      'test/a_test.dart dart',
      'test/src/ flutter $testChain',
      'test/src/w_test.dart flutter $testChain',
    ]);
  });

  test('run --dry-run', () async {
    expect(
      await dtkOut(['run', 'tool/hello.dart', '--dry-run', '--', 'a', 'b c']),
      'dart run tool/hello.dart a "b c"\n',
    );
    expect(
      await dtkOut([
        'run',
        'lib/main.dart',
        '-d',
        'emulator-5554',
        '--dry-run',
      ]),
      'flutter run -d emulator-5554 -t lib/main.dart\n',
    );
    // A part of an entry path, forced flutter, on this computer.
    expect(
      await dtkOut(['run', 'main_cli', '--flutter', '-d', 'vm', '--dry-run']),
      startsWith('flutter run -d '),
    );
    // The device of the env var, for a Flutter entry only.
    var environment = {'TK_FLUTTER_DEVICE_ID': 'pixel'};
    expect(
      await dtkOut([
        'run',
        'lib/main.dart',
        '--dry-run',
      ], environment: environment),
      endsWith('flutter run -d pixel -t lib/main.dart\n'),
    );
    expect(
      await dtkOut([
        'run',
        'tool/hello.dart',
        '--dry-run',
      ], environment: environment),
      'dart run tool/hello.dart\n',
    );
  });

  test('run: missing platform folder', () async {
    // Fails before running flutter.
    var result = await dtk(['run', 'lib/main.dart', '-d', 'linux']);
    expect(result.exitCode, 1, reason: '${result.stdout}');
    expect(
      result.stderr,
      contains(
        'No linux/ folder in $app, `flutter run -d linux -t lib/main.dart` '
        'needs it: add --create-platform '
        '(flutter create --platforms linux --no-pub .)',
      ),
    );
    // A dry run warns.
    result = await dtk(['run', 'lib/main.dart', '-d', 'linux', '--dry-run']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, 'flutter run -d linux -t lib/main.dart\n');
    expect(result.stderr, contains('No linux/ folder'));
    // Created first.
    expect(
      await dtkOut([
        'run',
        'lib/main.dart',
        '-d',
        'linux',
        '--create-platform',
        '--dry-run',
      ]),
      'flutter create --platforms linux --no-pub .\n'
      'flutter run -d linux -t lib/main.dart\n',
    );
    // A Dart run and unit tests need none, integration tests on a device do.
    result = await dtk(['run', 'tool/hello.dart', '--dry-run']);
    expect(result.stderr, isNot(contains('folder')));
    result = await dtk(['test', '-p', 'linux', '--dry-run']);
    expect(result.stderr, isNot(contains('folder')));
    write(
      'app/integration_test/app_test.dart',
      "import 'package:test/test.dart';",
    );
    try {
      result = await dtk(['test', 'integration_test', '-p', 'emulator-5554']);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('No android/ folder'));
    } finally {
      Directory(p.join(app, 'integration_test')).deleteSync(recursive: true);
    }
  });

  test('run: the entry asked', () async {
    // No input.
    var result = await dtk(['run', 'main', '--dry-run']);
    expect(result.exitCode, 1);
    expect(result.stdout, contains('1. lib/main.dart (flutter)'));
    expect(result.stderr, contains('No entry chosen (no input)'));
    // Picked on stdin.
    var process = await Process.start(Platform.resolvedExecutable, [
      cliScript,
      'run',
      'main',
      '--dry-run',
    ], workingDirectory: app);
    process.stdin.writeln('2');
    await process.stdin.close();
    var out = await process.stdout.transform(utf8.decoder).join();
    expect(await process.exitCode, 0);
    expect(out, endsWith('dart run lib/main_cli.dart\n'));
  });

  test('run: errors', () async {
    Future<String> error(List<String> arguments) async {
      var result = await dtk(arguments);
      expect(result.exitCode, 1, reason: '${result.stdout}');
      return result.stderr as String;
    }

    expect(
      await error(['run', 'nope', '--dry-run']),
      contains('No entry matching "nope"'),
    );
    expect(
      await error(['run', 'tool/hello.dart', '--dart', '--flutter']),
      contains('--dart or --flutter, not both'),
    );
    expect(
      await error(['run', 'a', 'b', '--dry-run']),
      contains('One entry at most'),
    );
    expect(
      await error(['test', 'nope', '--dry-run']),
      contains('Not found: nope'),
    );
  });

  test('test --dry-run', () async {
    expect(
      LineSplitter.split(
        await dtkOut([
          'test',
          '--dry-run',
          '-p',
          'vm',
          '-p',
          'chrome,node',
          '-p',
          'firefox',
          '-p',
          'emulator-5554',
        ]),
      ).toList(),
      [
        'flutter test test',
        'flutter test --platform chrome test',
        'dart test -p node test',
        'dart test -p firefox test',
        'flutter test -d emulator-5554 test',
      ],
    );
    expect(
      await dtkOut(['test', 'test/a_test.dart', '--dry-run']),
      'dart test test/a_test.dart\n',
    );
    expect(
      await dtkOut([
        'test',
        'test/a_test.dart',
        '--flutter',
        '--dry-run',
        '--',
        '--name',
        'x',
      ]),
      'flutter test test/a_test.dart --name x\n',
    );
  });

  test('run: dart run, exit code', () async {
    var result = await dtk([
      'run',
      'tool/hello.dart',
      '--',
      'a',
      'b',
    ], workingDirectory: hello);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('hello a,b'));
    result = await dtk(['run', 'tool/fail.dart'], workingDirectory: hello);
    expect(result.exitCode, 3);
  });
}
