import 'dart:convert';
import 'dart:io';

import 'package:process_run/shell.dart';

/// The env var holding the flutter device id to run on (`emulator-5554`),
/// read through process_run (`ds env var set TK_FLUTTER_DEVICE_ID <id>`):
/// the one the flutter device menu (`fdm`) sets.
const tkFlutterDeviceIdEnvKey = 'TK_FLUTTER_DEVICE_ID';

/// A device of `flutter devices --machine`, a `-d` of `flutter run` and
/// `flutter test`.
class DartRunDevice {
  /// The `-d` id (`emulator-5554`, `linux`, `chrome`).
  final String id;

  /// Name (`sdk gphone64 x86 64`, `Linux`).
  final String name;

  /// `android-arm64`, `android-x64`, `ios`, `darwin`, `linux-x64`,
  /// `windows-x64`, `web-javascript`.
  final String targetPlatform;

  /// True for an emulator or a simulator.
  final bool emulator;

  /// The OS version (`Android 16 (API 36)`), empty when unknown.
  final String sdk;

  /// Creates a device.
  const DartRunDevice({
    required this.id,
    required this.name,
    required this.targetPlatform,
    this.emulator = false,
    this.sdk = '',
  });

  /// An Android device or emulator.
  bool get isAndroid => targetPlatform.startsWith('android');

  /// An iOS device or simulator.
  bool get isIOS => targetPlatform == 'ios';

  /// A browser.
  bool get isWeb => targetPlatform.startsWith('web');

  /// This computer (`linux`, `macos`, `windows`).
  bool get isDesktop => !isAndroid && !isIOS && !isWeb;

  @override
  String toString() => '$name ($id)';
}

/// The supported devices of the output of `flutter devices --machine`.
List<DartRunDevice> parseFlutterDevicesMachine(String output) {
  // Anything before the json array (a flutter upgrade banner) is skipped.
  var start = output.indexOf('[');
  if (start < 0) {
    return [];
  }
  return (jsonDecode(output.substring(start)) as List)
      .cast<Map>()
      .where((map) => map['isSupported'] != false)
      .map(
        (map) => DartRunDevice(
          id: map['id'] as String,
          name: map['name'] as String,
          targetPlatform: map['targetPlatform'] as String,
          emulator: map['emulator'] == true,
          sdk: map['sdk'] as String? ?? '',
        ),
      )
      .toList();
}

/// The connected devices (`flutter devices --machine`).
Future<List<DartRunDevice>> getDartRunDevices() async {
  var result = await run(
    'flutter devices --machine',
    verbose: false,
    stdin: const Stream<List<int>>.empty(),
  );
  return parseFlutterDevicesMachine(result.outText);
}

/// An emulator or a simulator that can be launched (`flutter emulators`).
class DartRunEmulator {
  /// The `--launch` id (`Pixel_9`, `apple_ios_simulator`).
  final String id;

  /// Name.
  final String name;

  /// `android` or `ios`.
  final String platform;

  /// Creates an emulator.
  const DartRunEmulator({
    required this.id,
    required this.name,
    required this.platform,
  });

  @override
  String toString() => '$name ($id, $platform)';
}

/// The emulators of the output of `flutter emulators` (a table:
/// `Id • Name • Manufacturer • Platform`).
List<DartRunEmulator> parseFlutterEmulators(String output) {
  var emulators = <DartRunEmulator>[];
  for (var line in LineSplitter.split(output)) {
    var columns = line.split('•').map((column) => column.trim()).toList();
    if (columns.length < 4 || columns.first.isEmpty || columns.first == 'Id') {
      continue;
    }
    emulators.add(
      DartRunEmulator(id: columns[0], name: columns[1], platform: columns.last),
    );
  }
  return emulators;
}

/// The emulators and simulators that can be launched (`flutter emulators`).
Future<List<DartRunEmulator>> getDartRunEmulators() async {
  var result = await run(
    'flutter emulators',
    verbose: false,
    stdin: const Stream<List<int>>.empty(),
  );
  return parseFlutterEmulators(result.outText);
}

/// Launch the emulator [id] (`flutter emulators --launch`), it shows up in
/// the devices once booted.
Future<void> launchDartRunEmulator(String id) async {
  await run(
    'flutter emulators --launch ${shellArgument(id)}',
    verbose: false,
    stdin: const Stream<List<int>>.empty(),
  );
}

/// The flutter platform of this computer: `linux`, `macos` or `windows`.
String dartRunHostOs() => Platform.operatingSystem;
