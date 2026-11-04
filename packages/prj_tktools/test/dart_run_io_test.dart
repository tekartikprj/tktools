@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:process_run/shell.dart' show whichSync;
import 'package:tekartik_prj_tktools/dart_run.dart';
import 'package:test/test.dart';

void main() {
  late Directory top;
  late String app;

  void write(String path, String content) {
    File(join(top.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// A package config entry, [root] relative to top.
  Map<String, Object?> package(String name, String root) => {
    'name': name,
    'rootUri': '../../$root',
    'packageUri': 'lib/',
  };

  setUp(() {
    top = Directory.systemTemp.createTempSync('dart_run_io');
    app = join(top.path, 'app');
    // A fake Flutter SDK.
    write('sdk/packages/flutter/lib/widgets.dart', 'class Widget {}');
    write(
      'sdk/packages/flutter_test/lib/flutter_test.dart',
      "export 'package:flutter/widgets.dart';",
    );
    // A package importing Flutter, a pure Dart one with a conditional export.
    write(
      'deps/dep_flutter/lib/dep_flutter.dart',
      "import 'package:flutter/widgets.dart';",
    );
    write(
      'deps/dep_dart/lib/dep_dart.dart',
      "export 'src/stub.dart'\n"
          "    if (dart.library.ui) 'src/ui.dart'\n"
          "    if (dart.library.io) 'src/io.dart';",
    );
    write('deps/dep_dart/lib/src/stub.dart', '');
    write('deps/dep_dart/lib/src/io.dart', "import 'dart:io';");
    write('deps/dep_dart/lib/src/ui.dart', "import 'dart:ui';");
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
          package('dep_dart', 'deps/dep_dart'),
        ],
      }),
    );
    write(
      'app/lib/main.dart',
      "import 'package:dep_flutter/dep_flutter.dart';\nvoid main() {}",
    );
    write(
      'app/lib/main_cli.dart',
      "import 'src/cli.dart';\nFuture<void> main(List<String> args) async {}",
    );
    write(
      'app/lib/src/cli.dart',
      "import 'package:dep_dart/dep_dart.dart';\nimport 'a.dart';",
    );
    // A cycle.
    write('app/lib/src/a.dart', "import 'b.dart';");
    write('app/lib/src/b.dart', "import 'a.dart';");
    write(
      'app/lib/web_main.dart',
      "import 'src/a.dart' if (dart.library.js_interop) 'src/web.dart';\n"
          'void main() {}',
    );
    write('app/lib/src/web.dart', "import 'package:flutter/widgets.dart';");
    write(
      'app/lib/main_commented.dart',
      "// import 'package:flutter/widgets.dart';\n"
          "/* import 'package:flutter/widgets.dart'; */\n"
          'void main() {}',
    );
    // No main in the name, no main at all.
    write('app/lib/other.dart', 'void main() {}');
    write('app/lib/main_lib.dart', 'class Main { void main() {} }');
    write('app/bin/app.dart', 'void main() {}');
    write('app/tool/build.dart', 'void main() {}');
    write('app/tool/helper.dart', 'void helper() {}');
    write('app/tool/nested/pubspec.yaml', 'name: nested\n');
    write('app/tool/nested/run.dart', 'void main() {}');
    write('app/example/example.dart', "import 'dart:io';\nvoid main() {}");
    write('app/test/a_test.dart', "import 'package:test/test.dart';");
    write(
      'app/test/src/w_test.dart',
      "import 'package:flutter_test/flutter_test.dart';",
    );
    write('app/test/src/util.dart', '');
    write(
      'app/integration_test/app_test.dart',
      "import 'package:integration_test/integration_test.dart';",
    );
  });

  tearDown(() {
    top.deleteSync(recursive: true);
  });

  test('dartSourceDeclaresMain', () {
    expect(dartSourceDeclaresMain('void main() {}'), isTrue);
    expect(dartSourceDeclaresMain('main() {}'), isTrue);
    expect(
      dartSourceDeclaresMain('Future<void> main(List<String> args) async {}'),
      isTrue,
    );
    expect(dartSourceDeclaresMain('  void main() {}'), isFalse);
    expect(dartSourceDeclaresMain('// void main() {}'), isFalse);
    expect(dartSourceDeclaresMain('void mainly() {}'), isFalse);
  });

  test('dartSourceVmDirectiveUris', () {
    expect(
      dartSourceVmDirectiveUris(
        "import 'a.dart';\n"
        'export "b.dart" show B;\n'
        "part 'c.dart';\n"
        "part of 'd.dart';\n"
        "import 'e.dart' if (dart.library.html) 'f.dart'"
        " if (dart.library.io == 'true') 'g.dart';\n"
        "import 'h.dart' if (dart.library.ui) 'i.dart';\n",
      ),
      ['a.dart', 'b.dart', 'c.dart', 'g.dart', 'h.dart'],
    );
  });

  test('findDartRunEntries', () async {
    var entries = await findDartRunEntries(app);
    expect(entries.map((entry) => '$entry').toList(), [
      'lib/main.dart',
      'lib/main_cli.dart',
      'lib/main_commented.dart',
      'lib/web_main.dart',
      'example/example.dart',
      'bin/app.dart',
      'tool/build.dart',
      'test/',
      'test/a_test.dart',
      'test/src/',
      'test/src/w_test.dart',
      'integration_test/',
      'integration_test/app_test.dart',
    ]);
    expect(entries[7].folder, DartRunFolder.test);
    expect(entries[7].isDirectory, isTrue);
    expect(entries[7].isTest, isTrue);
  });

  test('flutterImportChain', () async {
    var scanner = DartImportScanner(app);
    expect(await scanner.flutterImportChain(join(app, 'lib', 'main.dart')), [
      'lib/main.dart',
      'package:dep_flutter/dep_flutter.dart',
      'package:flutter/widgets.dart',
    ]);
    // dart.library.io wins on the VM, a cycle ends.
    expect(await scanner.requiresFlutter('lib/main_cli.dart'), isFalse);
    expect(await scanner.requiresFlutter('lib/web_main.dart'), isFalse);
    expect(await scanner.requiresFlutter('lib/main_commented.dart'), isFalse);
    expect(await scanner.requiresFlutter('test/a_test.dart'), isFalse);
    // Through an export, and a package of the SDK not in the config.
    expect(await scanner.flutterImportChain('test/src/w_test.dart'), [
      'test/src/w_test.dart',
      'package:flutter_test/flutter_test.dart',
    ]);
    expect(
      await scanner.requiresFlutter('integration_test/app_test.dart'),
      isTrue,
    );
    // Read again from the cache.
    expect(await scanner.requiresFlutter('lib/main_cli.dart'), isFalse);
  });

  test('no package config', () async {
    File(join(app, '.dart_tool', 'package_config.json')).deleteSync();
    var scanner = DartImportScanner(app);
    // package:app resolved from the pubspec, flutter by its name.
    write('app/lib/main_self.dart', "import 'package:app/main.dart';");
    expect(await scanner.requiresFlutter('lib/main_self.dart'), isFalse);
    expect(await scanner.requiresFlutter('test/src/w_test.dart'), isTrue);
  });

  test('pub workspace member', () async {
    // The config of the workspace root lists the member.
    write('ws/pubspec.yaml', 'name: _\nworkspace:\n  - member\n');
    write('ws/member/pubspec.yaml', 'name: member\n');
    write(
      'ws/member/lib/main.dart',
      "import 'package:dep_flutter/dep_flutter.dart';",
    );
    write(
      'ws/.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'member', 'rootUri': '../member', 'packageUri': 'lib/'},
          package('dep_flutter', 'deps/dep_flutter'),
          package('flutter', 'sdk/packages/flutter'),
        ],
      }),
    );
    var scanner = DartImportScanner(join(top.path, 'ws', 'member'));
    expect(await scanner.flutterImportChain('lib/main.dart'), [
      'lib/main.dart',
      'package:dep_flutter/dep_flutter.dart',
      'package:flutter/widgets.dart',
    ]);
  });

  test('scanDartRunEntries', () async {
    var entries = await scanDartRunEntries(app);
    expect(
      entries
          .where((entry) => entry.flutter)
          .map((entry) => '${entry.entry}')
          .toList(),
      [
        'lib/main.dart',
        'test/',
        'test/src/',
        'test/src/w_test.dart',
        'integration_test/',
        'integration_test/app_test.dart',
      ],
    );
  });

  test('dartRunCommandLine', () {
    const main = DartRunEntry(path: 'lib/main.dart', folder: DartRunFolder.lib);
    const tool = DartRunEntry(
      path: 'tool/a b.dart',
      folder: DartRunFolder.tool,
    );
    const tests = DartRunEntry(
      path: 'test',
      folder: DartRunFolder.test,
      isDirectory: true,
    );
    const device = DartRunTarget.device(
      DartRunDevice(
        id: 'emulator-5554',
        name: 'sdk gphone',
        targetPlatform: 'android-x64',
      ),
    );
    String line(
      DartRunEntry entry,
      DartRunTarget target, {
      bool flutter = false,
      String args = '',
    }) => dartRunCommandLine(
      entry,
      target: target,
      flutter: flutter,
      args: args,
      hostOs: 'linux',
    );

    expect(
      line(main, DartRunTarget.vm, flutter: true),
      'flutter run -d linux -t lib/main.dart',
    );
    expect(line(tool, DartRunTarget.vm), 'dart run "tool/a b.dart"');
    expect(
      line(tool, DartRunTarget.vm, args: ' --verbose '),
      'dart run "tool/a b.dart" --verbose',
    );
    // A Dart main on a device: in a Flutter app.
    expect(line(main, device), 'flutter run -d emulator-5554 -t lib/main.dart');
    expect(
      line(main, DartRunTarget.chrome, flutter: true),
      'flutter run -d chrome -t lib/main.dart',
    );
    expect(line(tests, DartRunTarget.vm), 'dart test test');
    expect(line(tests, DartRunTarget.vm, flutter: true), 'flutter test test');
    expect(line(tests, DartRunTarget.chrome), 'dart test -p chrome test');
    expect(
      line(tests, DartRunTarget.chrome, flutter: true),
      'flutter test --platform chrome test',
    );
    expect(line(tests, DartRunTarget.node), 'dart test -p node test');
    expect(line(tests, DartRunTarget.firefox), 'dart test -p firefox test');
    expect(line(tests, device), 'flutter test -d emulator-5554 test');
    expect(
      dartTestCommandLine(
        ['test/a_test.dart', 'test/b c'],
        target: DartRunTarget.fromId('device:pixel'),
        flutter: true,
        args: '--name x',
      ),
      'flutter test -d pixel test/a_test.dart "test/b c" --name x',
    );
    expect(DartRunTarget.fromId('node'), DartRunTarget.node);
    expect(DartRunTarget.fromId('emulator-5554').device?.id, 'emulator-5554');
    expect(dartRunEntryFromPath('test/x_test.dart').isTest, isTrue);
    expect(dartRunEntryFromPath('other/x.dart').isTest, isFalse);
    expect(dartRunEntryFromPath('other/x_test.dart').isTest, isTrue);
    expect(
      dartRunIsFlutterRun(main, target: DartRunTarget.vm, flutter: false),
      isFalse,
    );
    expect(dartRunIsFlutterRun(main, target: device, flutter: false), isTrue);
    expect(dartRunIsFlutterRun(tests, target: device, flutter: true), isFalse);
    expect(DartRunTarget.node.canRun, isFalse);
    expect(device.id, 'device:emulator-5554');
  });

  test('parse devices and emulators', () {
    var devices = parseFlutterDevicesMachine(
      'A new version of Flutter is available\n'
      '${jsonEncode([
        {'name': 'sdk gphone64 x86 64', 'id': 'emulator-5554', 'isSupported': true, 'targetPlatform': 'android-x64', 'emulator': true, 'sdk': 'Android 16 (API 36)'},
        {'name': 'Linux', 'id': 'linux', 'isSupported': true, 'targetPlatform': 'linux-x64', 'emulator': false},
        {'name': 'Old', 'id': 'old', 'isSupported': false, 'targetPlatform': 'ios', 'emulator': false},
      ])}',
    );
    expect(devices.map((device) => device.id), ['emulator-5554', 'linux']);
    expect(devices.first.isAndroid, isTrue);
    expect(devices.first.emulator, isTrue);
    expect(devices.last.isDesktop, isTrue);

    var emulators = parseFlutterEmulators('''
3 available emulators:

Id                    • Name                  • Manufacturer • Platform
Pixel_9               • Pixel 9               • Google       • android
Nexus_One_API_28      • Nexus One API 28      •              • android
apple_ios_simulator   • iOS Simulator         • Apple        • ios

To run an emulator, run 'flutter emulators --launch <emulator id>'.
''');
    expect(emulators.map((emulator) => emulator.id), [
      'Pixel_9',
      'Nexus_One_API_28',
      'apple_ios_simulator',
    ]);
    expect(emulators.last.platform, 'ios');
  });

  test('dartRunFlutterPlatform', () {
    const main = DartRunEntry(path: 'lib/main.dart', folder: DartRunFolder.lib);
    const unitTests = DartRunEntry(
      path: 'test',
      folder: DartRunFolder.test,
      isDirectory: true,
    );
    const integrationTest = DartRunEntry(
      path: 'integration_test/app_test.dart',
      folder: DartRunFolder.integrationTest,
    );
    DartRunTarget device(String id, String targetPlatform) =>
        DartRunTarget.device(
          DartRunDevice(id: id, name: id, targetPlatform: targetPlatform),
        );
    String? platform(
      DartRunEntry entry,
      DartRunTarget target, {
      bool flutter = true,
    }) => dartRunFlutterPlatform(
      entry,
      target: target,
      flutter: flutter,
      hostOs: 'linux',
    );

    // A run.
    expect(platform(main, DartRunTarget.vm), 'linux');
    expect(platform(main, DartRunTarget.vm, flutter: false), isNull);
    expect(platform(main, DartRunTarget.chrome, flutter: false), 'web');
    expect(platform(main, device('pixel', 'android-arm64')), 'android');
    expect(platform(main, device('iphone', 'ios')), 'ios');
    expect(platform(main, device('macos', 'darwin')), 'macos');
    expect(platform(main, device('windows', 'windows-x64')), 'windows');
    expect(platform(main, device('chrome', 'web-javascript')), 'web');
    expect(platform(main, device('tv', 'fuchsia')), isNull);
    // A device id only (-d linux), its platform unknown.
    expect(platform(main, DartRunTarget.fromId('linux')), 'linux');
    expect(platform(main, DartRunTarget.fromId('emulator-5554')), 'android');
    expect(platform(main, DartRunTarget.fromId('pixel')), isNull);
    // A test: integration tests on a device only.
    expect(platform(unitTests, DartRunTarget.vm), isNull);
    expect(platform(unitTests, DartRunTarget.fromId('linux')), isNull);
    expect(platform(integrationTest, DartRunTarget.vm), isNull);
    expect(platform(integrationTest, DartRunTarget.fromId('linux')), 'linux');
    expect(
      dartTestFlutterPlatform([
        'test/a_test.dart',
        'integration_test',
      ], target: device('pixel', 'android-x64')),
      'android',
    );

    expect(
      flutterCreatePlatformsCommandLine(['linux', 'web']),
      'flutter create --platforms linux,web --no-pub .',
    );
    expect(
      flutterCreatePlatformsCommandLine(['linux'], projectName: 'my_app'),
      'flutter create --platforms linux --no-pub --project-name my_app .',
    );
  });

  test(
    'flutterCreatePlatforms',
    () async {
      // A folder name that is not the package name, no lib/main.dart, no
      // test/: flutter create would add them.
      var project = join(top.path, 'my_folder');
      write('my_folder/pubspec.yaml', '''
name: fc_app
environment:
  sdk: ^3.9.0
dependencies:
  flutter:
    sdk: flutter
''');
      write(
        'my_folder/lib/main_x.dart',
        "import 'package:flutter/widgets.dart';\n"
            'void main() => runApp(const SizedBox());\n',
      );
      write('my_folder/README.md', 'mine');
      write('my_folder/android/keep.txt', 'an existing platform');
      expect(flutterProjectExistingPlatforms(project), ['android']);

      List<String> files() =>
          Directory(project)
              .listSync(recursive: true)
              .whereType<File>()
              .map((file) => relative(file.path, from: project))
              .where(
                (path) =>
                    !path.startsWith('linux') && !path.startsWith('.dart_tool'),
              )
              .toList()
            ..sort();
      var before = files();
      expect(await flutterCreatePlatforms(project, ['android', 'linux']), [
        'linux',
      ]);
      expect(flutterProjectExistingPlatforms(project), ['android', 'linux']);
      // Only linux/ was added, named after the package.
      expect(files(), before);
      expect(File(join(project, 'README.md')).readAsStringSync(), 'mine');
      expect(
        File(join(project, 'linux', 'CMakeLists.txt')).readAsStringSync(),
        contains('set(BINARY_NAME "fc_app")'),
      );
      // Nothing missing: no flutter create.
      expect(await flutterCreatePlatforms(project, ['linux']), isEmpty);
    },
    skip: whichSync('flutter') == null ? 'flutter not found' : null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
