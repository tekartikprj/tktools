@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:process_run/shell.dart';
import 'package:test/test.dart';

import 'src/test_kernel.dart';

/// dtk pub menu items, run as a sub process on temp exports, the user prefs
/// in a temp folder (TEKARTIK_PROCESS_RUN_USER_APP_DATA_PATH).
void main() {
  late Directory tmp;
  late String menuProgram;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('dtk_pub_menu');
    menuProgram = await compileTestScript(
      absolute(join('test', 'src', 'dtk_pub_menu_main.dart')),
      tmp.path,
    );
  });

  tearDownAll(() async {
    await tmp.delete(recursive: true);
  });

  /// Run the menu [commands], each prompt answered on stdin once displayed
  /// ([answers]: the prompt text, the answer), then stdin closed: the menu
  /// exits once the item is done.
  ///
  /// The answers cannot be command line arguments: the next argument runs
  /// as a menu command before the item prompts again.
  Future<void> menu(
    List<String> commands, {
    List<(String, String)> answers = const [],
  }) async {
    var input = StreamController<List<int>>();
    var output = StreamController<List<int>>();
    var pending = List.of(answers);
    var since = StringBuffer();
    void closeInput() {
      if (!input.isClosed) {
        input.close();
      }
    }

    if (pending.isEmpty) {
      closeInput();
    }
    // A prompt never displayed: stdin closed, the menu exits.
    var timer = Timer(const Duration(seconds: 60), closeInput);
    output.stream.transform(utf8.decoder).listen((text) {
      since.write(text);
      if (pending.isEmpty) {
        return;
      }
      var (prompt, answer) = pending.first;
      var seen = since.toString();
      if (seen.contains(prompt) && seen.trimRight().endsWith('>')) {
        pending.removeAt(0);
        since.clear();
        input.add(utf8.encode('$answer\n'));
        if (pending.isEmpty) {
          closeInput();
        }
      }
    });
    var result =
        await Shell(
          environment: {
            'TEKARTIK_PROCESS_RUN_USER_APP_DATA_PATH': join(
              tmp.path,
              'app_data',
            ),
          },
          throwOnError: false,
          verbose: false,
          stdin: input.stream,
          stdout: output.sink,
        ).runExecutableArguments(Platform.resolvedExecutable, [
          menuProgram,
          tmp.path,
          ...commands,
        ]);
    timer.cancel();
    await output.close();
    expect(pending, isEmpty, reason: '${result.stdout}\n${result.stderr}');
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  String? read(String name) {
    var file = File(join(tmp.path, name));
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  test('set ref writes the tkpub registry', () async {
    // gitRef > set ref (prompt)
    await menu(['0', '1'], answers: [('ref (default:', 'my_ref')]);
    expect(read('tkpub.jsonl'), contains('"gitRef":"my_ref"'));
    // Not the shared dependencies.
    expect(read('dtk_dep.jsonl'), isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('add writes the package', () async {
    // packages > add
    await menu(
      ['1', '1'],
      answers: [
        ('Package name', 'my_pkg'),
        ('gitUrl', 'https://github.com/my_org/my_pkg.dart'),
        ('gitPath', ''),
      ],
    );
    expect(read('tkpub.jsonl'), contains('["my_pkg",'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
