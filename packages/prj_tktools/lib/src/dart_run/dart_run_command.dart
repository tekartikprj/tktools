import 'package:process_run/shell.dart';

import 'dart_run_device.dart';
import 'dart_run_entry.dart';

/// The kinds of [DartRunTarget].
enum DartRunTargetKind {
  /// The Dart VM on this computer: `dart run`, `dart test`, `flutter test`,
  /// `flutter run -d <this computer>`.
  vm,

  /// Chrome: `dart test -p chrome`, `flutter test --platform chrome`,
  /// `flutter run -d chrome`.
  chrome,

  /// Node, for the tests only: `dart test -p node`.
  node,

  /// Firefox, for the tests only: `dart test -p firefox`.
  firefox,

  /// A device of `flutter devices`: `flutter run -d`, `flutter test -d`.
  device,
}

/// Where something is run or tested.
class DartRunTarget {
  /// What it is.
  final DartRunTargetKind kind;

  /// The device, for [DartRunTargetKind.device] only.
  final DartRunDevice? device;

  const DartRunTarget._(this.kind) : device = null;

  /// The Dart VM, this computer.
  static const vm = DartRunTarget._(DartRunTargetKind.vm);

  /// Chrome.
  static const chrome = DartRunTarget._(DartRunTargetKind.chrome);

  /// Node (tests only).
  static const node = DartRunTarget._(DartRunTargetKind.node);

  /// Firefox (tests only).
  static const firefox = DartRunTarget._(DartRunTargetKind.firefox);

  /// The targets that are not devices.
  static const builtIn = [vm, chrome, node, firefox];

  /// A device of `flutter devices`.
  const DartRunTarget.device(DartRunDevice this.device)
    : kind = DartRunTargetKind.device;

  /// The target of [id]: `vm`, `chrome`, `node`, `firefox`, `device:<id>` or
  /// a flutter device id (not checked, `flutter` tells when it is unknown).
  factory DartRunTarget.fromId(String id) {
    for (var target in builtIn) {
      if (target.id == id) {
        return target;
      }
    }
    var deviceId = id.startsWith('device:') ? id.substring(7) : id;
    return DartRunTarget.device(
      DartRunDevice(id: deviceId, name: deviceId, targetPlatform: ''),
    );
  }

  /// A stable id: `vm`, `chrome`, `node`, `firefox` or `device:<id>`.
  String get id => device == null ? kind.name : 'device:${device!.id}';

  /// Displayed name.
  String get label => switch (kind) {
    DartRunTargetKind.vm => 'This computer (VM)',
    DartRunTargetKind.chrome => 'Chrome',
    DartRunTargetKind.node => 'Node',
    DartRunTargetKind.firefox => 'Firefox',
    DartRunTargetKind.device => device!.name,
  };

  /// True when a run (not a test) can go there: node and Firefox are for
  /// the tests only.
  bool get canRun =>
      kind != DartRunTargetKind.node && kind != DartRunTargetKind.firefox;

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(Object other) => other is DartRunTarget && other.id == id;

  @override
  String toString() => label;
}

/// The command line, run in the project, running or testing [entry] on
/// [target].
///
/// [flutter] tells whether it needs Flutter (see `DartImportScanner`; for a
/// test folder, whether one of its tests does). Any combination gives a
/// command, the ones that cannot work fail when run (`dart test -p node` of
/// a Flutter test). [args] are added at the end (program arguments of
/// `dart run`, options of the other commands), [hostOs] is this computer's
/// platform by default.
///
/// - run: `dart run <file>` on the VM for a Dart file,
///   `flutter run -d <id> -t <file>` otherwise (a Dart `main` runs in a
///   Flutter app too, its output in the console);
/// - test: `dart test [-p <platform>] <path>`,
///   `flutter test [--platform chrome] <path>`,
///   `flutter test <path> -d <id>` on a device.
String dartRunCommandLine(
  DartRunEntry entry, {
  required DartRunTarget target,
  required bool flutter,
  String args = '',
  String? hostOs,
}) {
  if (entry.isTest) {
    return dartTestCommandLine(
      [entry.path],
      target: target,
      flutter: flutter,
      args: args,
    );
  }
  var path = shellArgument(entry.path);
  var device = target.device;
  var deviceId = shellArgument(device?.id ?? '');
  var parts = <String>[
    ...switch (target.kind) {
      DartRunTargetKind.vm =>
        flutter
            ? ['flutter', 'run', '-d', hostOs ?? dartRunHostOs(), '-t', path]
            : ['dart', 'run', path],
      DartRunTargetKind.chrome ||
      DartRunTargetKind.node ||
      DartRunTargetKind.firefox => [
        'flutter',
        'run',
        '-d',
        'chrome',
        '-t',
        path,
      ],
      DartRunTargetKind.device => [
        'flutter',
        'run',
        '-d',
        deviceId,
        '-t',
        path,
      ],
    },
    if (args.trim().isNotEmpty) args.trim(),
  ];
  return parts.join(' ');
}

/// The command line, run in the project, testing [paths] (files or folders
/// relative to the project) on [target] (see [dartRunCommandLine]):
/// `dart test [-p <platform>]`, `flutter test [--platform chrome]`,
/// `flutter test -d <id>` on a device.
String dartTestCommandLine(
  List<String> paths, {
  required DartRunTarget target,
  required bool flutter,
  String args = '',
}) {
  var deviceId = shellArgument(target.device?.id ?? '');
  return [
    ...switch (target.kind) {
      DartRunTargetKind.vm => flutter ? ['flutter', 'test'] : ['dart', 'test'],
      DartRunTargetKind.chrome =>
        flutter
            ? ['flutter', 'test', '--platform', 'chrome']
            : ['dart', 'test', '-p', 'chrome'],
      DartRunTargetKind.node => ['dart', 'test', '-p', 'node'],
      DartRunTargetKind.firefox => ['dart', 'test', '-p', 'firefox'],
      DartRunTargetKind.device => ['flutter', 'test', '-d', deviceId],
    },
    ...paths.map(shellArgument),
    if (args.trim().isNotEmpty) args.trim(),
  ].join(' ');
}

/// True when the command of [entry] on [target] is a `flutter run`
/// (interactive: hot reload, hot restart and quit keys).
bool dartRunIsFlutterRun(
  DartRunEntry entry, {
  required DartRunTarget target,
  required bool flutter,
}) => !entry.isTest && (flutter || target.kind != DartRunTargetKind.vm);
