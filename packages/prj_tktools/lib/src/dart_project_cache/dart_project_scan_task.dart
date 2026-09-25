import 'package:fs_shim/fs_shim.dart';

import 'dart_project.dart';
import 'dart_project_scan_isolate.dart';
import 'dart_project_scanner.dart';

/// A scan running, see [startDartProjectScan].
abstract class DartProjectScanTask {
  /// Canonical path of the folder scanned.
  String get path;

  /// True once [cancel] was called.
  bool get cancelled;

  /// Stop the scan, [result] then holds what was found so far.
  void cancel();

  /// What was found, once done (or cancelled). Never throws, what could not
  /// be scanned is reported in [DartProjectScanResult.errors].
  Future<DartProjectScanResult> get result;
}

/// Start scanning the folder [path] of [fs] for dart projects.
///
/// The io file system is scanned in a background isolate ([isolate] true by
/// default then): walking a big tree takes tens of thousands of disk
/// accesses, done one after the other, that must not wait for the frames of
/// a user interface running meanwhile. Any other file system is scanned
/// here.
///
/// [onProgress] is called with what was found so far, at most once per
/// [progressInterval].
DartProjectScanTask startDartProjectScan(
  FileSystem fs,
  String path, {
  void Function(DartProjectScanResult found)? onProgress,
  Duration? progressInterval,
  bool? isolate,
}) {
  var canonicalPath = dartProjectCanonicalPath(fs, path);
  isolate ??= fs.name == 'io' && dartProjectScanIsolateSupported;
  if (isolate) {
    return startDartProjectScanIsolate(
      canonicalPath,
      onProgress: onProgress,
      progressInterval: progressInterval,
    );
  }
  return _LocalScanTask(
    DartProjectScanner(
      fs,
      canonicalPath,
      onProgress: onProgress,
      progressInterval: progressInterval,
    ),
  );
}

/// A scan in the current isolate.
class _LocalScanTask implements DartProjectScanTask {
  final DartProjectScanner _scanner;

  @override
  final Future<DartProjectScanResult> result;

  /// Started right away.
  _LocalScanTask(DartProjectScanner scanner)
    : _scanner = scanner,
      result = scanner.scan();

  @override
  String get path => _scanner.path;

  @override
  bool get cancelled => _scanner.cancelled;

  @override
  void cancel() => _scanner.cancel();
}
