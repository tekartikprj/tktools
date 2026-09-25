import 'dart_project_scan_task.dart';
import 'dart_project_scanner.dart';

/// False, no isolate on this platform.
const dartProjectScanIsolateSupported = false;

/// Not supported on this platform.
DartProjectScanTask startDartProjectScanIsolate(
  String path, {
  void Function(DartProjectScanResult found)? onProgress,
  Duration? progressInterval,
}) => throw UnsupportedError('No scan isolate on this platform');
