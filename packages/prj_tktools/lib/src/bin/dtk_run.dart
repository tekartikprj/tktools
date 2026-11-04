import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:process_run/shell.dart';
import 'package:tekartik_prj_tktools/dart_run.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';

const _optionDevice = 'device';
const _optionPlatform = 'platform';
const _optionProject = 'project';
const _optionLaunch = 'launch';
const _flagDart = 'dart';
const _flagFlutter = 'flutter';
const _flagList = 'list';
const _flagDryRun = 'dry-run';
const _flagJson = 'json';
const _flagCreatePlatform = 'create-platform';

/// The help of --create-platform.
const _createPlatformHelp =
    'Create the platform folder the command needs when missing (linux/ for '
    'flutter run -d linux): flutter create --platforms <platform>, the '
    'other files it adds removed';

/// Fails when the project at [projectPath] has no [platform] folder (that
/// [command] needs, see `dartRunFlutterPlatform`), unless [create] creates
/// it; a dry run prints the create command or the warning.
Future<void> _checkFlutterPlatform(
  String projectPath,
  String? platform, {
  required String command,
  required bool create,
  required bool dryRun,
}) async {
  if (platform == null ||
      flutterProjectExistingPlatforms(projectPath).contains(platform)) {
    return;
  }
  var createCommand = flutterCreatePlatformsCommandLine([platform]);
  if (create) {
    if (dryRun) {
      stdout.writeln(createCommand);
    } else {
      stdout.writeln('Creating $platform/ ($createCommand)');
      await flutterCreatePlatforms(projectPath, [platform]);
    }
    return;
  }
  var message =
      'No $platform/ folder in $projectPath, `$command` needs it: add '
      '--$_flagCreatePlatform ($createCommand)';
  if (dryRun) {
    stderr.writeln(message);
    return;
  }
  throw StateError(message);
}

/// The hint when no device can be chosen.
const _deviceHint =
    'use -d <device id|vm|chrome> or set $tkFlutterDeviceIdEnvKey '
    '(ds env var set $tkFlutterDeviceIdEnvKey <id>)';

/// `dtk run`: run a main, example, bin or tool file of a dart project, with
/// `dart run` or `flutter run -d <device>` when it imports Flutter.
class DtkRunCommand extends ShellBinCommand {
  /// dtk run command
  DtkRunCommand()
    : super(
        name: 'run',
        description:
            'Run a lib main file, example, bin or tool script of the project: '
            'dart run, or flutter run -d <device> when it imports Flutter '
            '(dtk run [entry] [-d <device>] [-- args])',
        parser: ArgParser(allowTrailingOptions: true),
      ) {
    parser
      ..addOption(
        _optionDevice,
        abbr: 'd',
        help:
            'vm, chrome or a flutter device id (default: vm for a Dart '
            'entry; $tkFlutterDeviceIdEnvKey, the only device, or asked for '
            'a Flutter one)',
      )
      ..addOption(
        _optionProject,
        help:
            'The project (default: the one holding the entry or the current '
            'folder)',
      )
      ..addFlag(_flagDart, negatable: false, help: 'Force dart')
      ..addFlag(_flagFlutter, negatable: false, help: 'Force flutter')
      ..addFlag(
        _flagList,
        negatable: false,
        help:
            'List what the project runs and tests, dart or flutter, how it '
            'reaches Flutter',
      )
      ..addFlag(
        _flagDryRun,
        negatable: false,
        help: 'Print the command line, do not run it',
      )
      ..addFlag(
        _flagCreatePlatform,
        negatable: false,
        help: _createPlatformHelp,
      );
  }

  @override
  FutureOr<bool> onRun() async {
    var (positional, extra) = _splitExtraArgs(results);
    if (positional.length > 1) {
      throw ArgumentError(
        'One entry at most (${positional.join(' ')}), the program arguments '
        'go after --',
      );
    }
    var forced = _forcedFlutter(results);
    var query = positional.firstOrNull;
    var projectPath = _projectPath(results.option(_optionProject), query);
    var entries = await scanDartRunEntries(projectPath);
    if (results.flag(_flagList)) {
      _printEntries(entries);
      return true;
    }
    var entry = await _runEntry(projectPath, entries, query);
    var flutter = forced ?? entry.flutter;
    var target = await _target(results.option(_optionDevice), flutter: flutter);
    var command = dartRunCommandLine(
      entry.entry,
      target: target,
      flutter: flutter,
      args: shellArguments(extra),
    );
    var dryRun = results.flag(_flagDryRun);
    await _checkFlutterPlatform(
      projectPath,
      dartRunFlutterPlatform(entry.entry, target: target, flutter: flutter),
      command: command,
      create: results.flag(_flagCreatePlatform),
      dryRun: dryRun,
    );
    if (dryRun) {
      stdout.writeln(command);
      return true;
    }
    exitCode = await _run(projectPath, command, withStdin: true);
    return true;
  }
}

/// `dtk test`: `dart test` or `flutter test` (from the imports) of files or
/// folders, on one or more platforms.
class DtkTestCommand extends ShellBinCommand {
  /// dtk test command
  DtkTestCommand()
    : super(
        name: 'test',
        description:
            'Test files or folders (test/ by default) with dart test or '
            'flutter test (from the imports) on platforms: vm, chrome, node, '
            'firefox or a flutter device (flutter test -d), each one run, '
            'a summary at the end',
        parser: ArgParser(allowTrailingOptions: true),
      ) {
    parser
      ..addMultiOption(
        _optionPlatform,
        abbr: 'p',
        help:
            'vm (default), chrome, node, firefox or a flutter device id, '
            'repeatable (-p vm -p chrome or -p vm,chrome), unsupported ones '
            'are tried too',
      )
      ..addOption(
        _optionProject,
        help:
            'The project (default: the one holding the first path or the '
            'current folder)',
      )
      ..addFlag(_flagDart, negatable: false, help: 'Force dart test')
      ..addFlag(_flagFlutter, negatable: false, help: 'Force flutter test')
      ..addFlag(
        _flagDryRun,
        negatable: false,
        help: 'Print the command lines, do not run them',
      )
      ..addFlag(
        _flagCreatePlatform,
        negatable: false,
        help: _createPlatformHelp,
      );
  }

  @override
  FutureOr<bool> onRun() async {
    var (positional, extra) = _splitExtraArgs(results);
    var projectPath = _projectPath(
      results.option(_optionProject),
      positional.firstOrNull,
    );
    var paths = <String>[];
    for (var path in positional.isEmpty ? ['test'] : positional) {
      var absolute = p.normalize(
        p.absolute(positional.isEmpty ? p.join(projectPath, path) : path),
      );
      if (!FileSystemEntity.isDirectorySync(absolute) &&
          !FileSystemEntity.isFileSync(absolute)) {
        throw ArgumentError('Not found: $path');
      }
      if (!p.isWithin(projectPath, absolute) && absolute != projectPath) {
        throw ArgumentError('$path is not in the project $projectPath');
      }
      paths.add(_posixRelative(absolute, projectPath));
    }
    var flutter =
        _forcedFlutter(results) ?? await _testsNeedFlutter(projectPath, paths);
    var platforms = results.multiOption(_optionPlatform);
    if (platforms.isEmpty) {
      platforms = ['vm'];
    }
    var dryRun = results.flag(_flagDryRun);
    var outcomes = <(String, String, int)>[];
    for (var platform in platforms) {
      var target = DartRunTarget.fromId(platform);
      var command = dartTestCommandLine(
        paths,
        target: target,
        flutter: flutter,
        args: shellArguments(extra),
      );
      await _checkFlutterPlatform(
        projectPath,
        dartTestFlutterPlatform(paths, target: target),
        command: command,
        create: results.flag(_flagCreatePlatform),
        dryRun: dryRun,
      );
      if (dryRun) {
        stdout.writeln(command);
        continue;
      }
      outcomes.add((
        platform,
        command,
        await _run(projectPath, command, withStdin: false),
      ));
    }
    if (outcomes.isNotEmpty) {
      stdout.writeln('dtk test summary:');
      for (var (platform, command, code) in outcomes) {
        stdout.writeln(
          '  $platform: ${code == 0 ? 'ok' : 'FAILED (exit code $code)'}'
          '  $command',
        );
      }
      if (outcomes.any((outcome) => outcome.$3 != 0)) {
        exitCode = 1;
      }
    }
    return true;
  }
}

/// `dtk devices`: the connected devices and the emulators, launch one.
class DtkDevicesCommand extends ShellBinCommand {
  /// dtk devices command
  DtkDevicesCommand()
    : super(
        name: 'devices',
        description:
            'The flutter devices and the emulators/simulators that can be '
            'launched (--launch <emulator id>)',
        parser: ArgParser(allowTrailingOptions: true),
      ) {
    parser
      ..addOption(_optionLaunch, help: 'Launch the emulator of this id')
      ..addFlag(_flagJson, negatable: false, help: 'Json output');
  }

  @override
  FutureOr<bool> onRun() async {
    var launch = results.option(_optionLaunch);
    if (launch != null) {
      stdout.writeln('Launching $launch (listed in dtk devices once booted)');
      await launchDartRunEmulator(launch);
      return true;
    }
    var devices = await getDartRunDevices();
    var emulators = await getDartRunEmulators();
    if (results.flag(_flagJson)) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'devices': [
            for (var device in devices)
              {
                'id': device.id,
                'name': device.name,
                'targetPlatform': device.targetPlatform,
                'emulator': device.emulator,
              },
          ],
          'emulators': [
            for (var emulator in emulators)
              {
                'id': emulator.id,
                'name': emulator.name,
                'platform': emulator.platform,
              },
          ],
        }),
      );
      return true;
    }
    stdout.writeln('Devices (-d <id>; also vm, chrome, node, firefox):');
    for (var device in devices) {
      stdout.writeln(
        '  ${device.id}  ${device.name} (${device.targetPlatform}'
        '${device.emulator ? ', emulator' : ''})',
      );
    }
    stdout.writeln('Emulators (dtk devices --launch <id>):');
    for (var emulator in emulators) {
      stdout.writeln(
        '  ${emulator.id}  ${emulator.name} (${emulator.platform})',
      );
    }
    return true;
  }
}

/// The positional arguments and the ones after `--`.
(List<String>, List<String>) _splitExtraArgs(ArgResults results) {
  var arguments = results.arguments;
  var index = arguments.indexOf('--');
  var extra = index < 0 ? <String>[] : arguments.sublist(index + 1);
  var rest = results.rest;
  return (rest.sublist(0, rest.length - extra.length), extra);
}

/// True for --flutter, false for --dart, null for neither.
bool? _forcedFlutter(ArgResults results) {
  var dart = results.flag(_flagDart);
  var flutter = results.flag(_flagFlutter);
  if (dart && flutter) {
    throw ArgumentError('--dart or --flutter, not both');
  }
  return flutter ? true : (dart ? false : null);
}

/// The project: [option], else the one holding [path] when it exists, else
/// the one holding the current folder.
String _projectPath(String? option, String? path) {
  String? project;
  if (option != null) {
    project = dartRunProjectRoot(option);
  } else if (path != null &&
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
    project = dartRunProjectRoot(path);
  } else {
    project = dartRunProjectRoot(Directory.current.path);
  }
  if (project == null) {
    throw StateError(
      'No dart project (pubspec.yaml) in ${option ?? path ?? Directory.current.path} '
      'or its parents',
    );
  }
  return project;
}

String _posixRelative(String path, String projectPath) {
  var relative = p.relative(path, from: projectPath);
  return p.posix.joinAll(p.split(relative));
}

/// One line per entry: its path, dart or flutter, how it reaches Flutter.
void _printEntries(List<DartRunProjectEntry> entries) {
  var width = entries.fold(
    0,
    (width, entry) => entry.entry.toString().length > width
        ? entry.entry.toString().length
        : width,
  );
  for (var entry in entries) {
    var chain = entry.flutterChain;
    stdout.writeln(
      '${entry.entry.toString().padRight(width)}  '
              '${entry.flutter ? 'flutter' : 'dart   '}'
              '${chain == null ? '' : '  ${chain.join(' -> ')}'}'
          .trimRight(),
    );
  }
}

/// The entry to run: [query] (a file, or a part of an entry path), else the
/// only one, else the one picked.
Future<DartRunProjectEntry> _runEntry(
  String projectPath,
  List<DartRunProjectEntry> entries,
  String? query,
) async {
  var runnables = entries.where((entry) => !entry.entry.isTest).toList();
  if (query != null && FileSystemEntity.isFileSync(query)) {
    var path = _posixRelative(p.absolute(query), projectPath);
    var known = entries.where((entry) => entry.entry.path == path).firstOrNull;
    return known ??
        DartRunProjectEntry(
          dartRunEntryFromPath(path),
          flutterChain: await DartImportScanner(
            projectPath,
          ).flutterImportChain(p.absolute(query)),
        );
  }
  var candidates = runnables;
  if (query != null && !FileSystemEntity.isDirectorySync(query)) {
    candidates = runnables
        .where((entry) => entry.entry.path.contains(query))
        .toList();
    if (candidates.isEmpty) {
      throw ArgumentError('No entry matching "$query", see dtk run --list');
    }
  }
  if (candidates.isEmpty) {
    throw StateError(
      'Nothing to run in $projectPath (lib main files, example, bin, tool), '
      'see dtk run --list',
    );
  }
  if (candidates.length == 1) {
    return candidates.single;
  }
  return _pick<DartRunProjectEntry>(
    'Entry',
    candidates,
    (entry) => '${entry.entry} (${entry.flutter ? 'flutter' : 'dart'})',
    hint: 'pass the entry (dtk run <path>), see dtk run --list',
  );
}

/// The target: [option], else this computer for a Dart entry, else
/// [tkFlutterDeviceIdEnvKey], the only device, or the one picked.
Future<DartRunTarget> _target(String? option, {required bool flutter}) async {
  if (option != null) {
    return DartRunTarget.fromId(option);
  }
  if (!flutter) {
    return DartRunTarget.vm;
  }
  var envDeviceId = ShellEnvironment().vars[tkFlutterDeviceIdEnvKey];
  if (envDeviceId != null && envDeviceId.isNotEmpty) {
    stdout.writeln('Device $envDeviceId (from $tkFlutterDeviceIdEnvKey)');
    return DartRunTarget.fromId(envDeviceId);
  }
  var devices = await getDartRunDevices();
  if (devices.isEmpty) {
    throw StateError(
      'No device found: launch an emulator (dtk devices --launch <id>) or '
      '$_deviceHint',
    );
  }
  if (devices.length == 1) {
    stdout.writeln('Device ${devices.single}');
    return DartRunTarget.device(devices.single);
  }
  var device = _pick(
    'Device',
    devices,
    (device) =>
        '${device.name} (${device.id}, ${device.targetPlatform}'
        '${device.emulator ? ', emulator' : ''})',
    hint: _deviceHint,
  );
  stdout.writeln(
    'Not to be asked again: ds env var set $tkFlutterDeviceIdEnvKey '
    '${device.id}',
  );
  return DartRunTarget.device(device);
}

/// Pick one of [items] by its number, read on stdin (works in a terminal and
/// in an IDE run console).
T _pick<T>(
  String what,
  List<T> items,
  String Function(T item) label, {
  required String hint,
}) {
  for (var i = 0; i < items.length; i++) {
    stdout.writeln('${i + 1}. ${label(items[i])}');
  }
  while (true) {
    stdout.write('$what [1-${items.length}]: ');
    var line = stdin.readLineSync();
    if (line == null) {
      throw StateError('No ${what.toLowerCase()} chosen (no input): $hint');
    }
    var index = int.tryParse(line.trim());
    if (index != null && index >= 1 && index <= items.length) {
      return items[index - 1];
    }
  }
}

/// True when one of the test [paths] (relative to the project) needs
/// Flutter.
Future<bool> _testsNeedFlutter(String projectPath, List<String> paths) async {
  var scanner = DartImportScanner(projectPath);
  for (var path in paths) {
    var absolute = p.join(projectPath, path);
    var files = FileSystemEntity.isDirectorySync(absolute)
        ? findDartTestFiles(absolute)
        : [absolute];
    if (await scanner.anyRequiresFlutter(files)) {
      return true;
    }
  }
  return false;
}

/// Run [command] in the project, its exit code. [withStdin] forwards the
/// keys (flutter run hot reload, a script prompt).
Future<int> _run(
  String projectPath,
  String command, {
  required bool withStdin,
}) async {
  var shell = Shell(
    workingDirectory: projectPath,
    throwOnError: false,
    stdin: withStdin ? sharedStdIn : null,
  );
  try {
    var results = await shell.run(command);
    return results.isEmpty ? 0 : results.last.exitCode;
  } finally {
    if (withStdin) {
      // Otherwise the stdin subscription keeps the process alive.
      await sharedStdIn.terminate();
    }
  }
}
