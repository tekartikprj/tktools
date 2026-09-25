import 'dart:async';
import 'dart:isolate';

import 'package:fs_shim/fs_shim.dart';

import 'dart_project_scan_task.dart';
import 'dart_project_scanner.dart';

/// True, the io file system can be scanned in a background isolate.
const dartProjectScanIsolateSupported = true;

/// Scan the io folder [path] (canonical) in a background isolate.
DartProjectScanTask startDartProjectScanIsolate(
  String path, {
  void Function(DartProjectScanResult found)? onProgress,
  Duration? progressInterval,
}) => _IsolateScanTask(
  path,
  onProgress: onProgress,
  progressInterval: progressInterval,
).._start();

/// Messages sent by the scan isolate.
sealed class _ScanMessage {}

class _Progress extends _ScanMessage {
  final DartProjectScanResult found;

  _Progress(this.found);
}

class _Done extends _ScanMessage {
  final DartProjectScanResult result;

  _Done(this.result);
}

/// A scan in a background isolate, killed when cancelled.
class _IsolateScanTask implements DartProjectScanTask {
  @override
  final String path;
  final void Function(DartProjectScanResult found)? onProgress;
  final Duration? progressInterval;

  final _port = ReceivePort();
  final _result = Completer<DartProjectScanResult>();
  final _started = DateTime.now();
  Isolate? _isolate;
  DartProjectScanResult? _found;
  var _cancelled = false;

  _IsolateScanTask(this.path, {this.onProgress, this.progressInterval});

  @override
  bool get cancelled => _cancelled;

  @override
  Future<DartProjectScanResult> get result => _result.future;

  Future<void> _start() async {
    _port.listen(_onMessage);
    try {
      var isolate = await Isolate.spawn(
        _scanMain,
        (_port.sendPort, path, progressInterval),
        onError: _port.sendPort,
        onExit: _port.sendPort,
        debugName: 'dart_project_scan',
      );
      _isolate = isolate;
      if (_cancelled) {
        isolate.kill(priority: Isolate.immediate);
      }
    } catch (e) {
      _complete(_foundSoFar(errors: ['$path: $e']));
    }
  }

  void _onMessage(Object? message) {
    switch (message) {
      case _Progress(:var found):
        _found = found;
        if (!_cancelled) {
          onProgress?.call(found);
        }
      case _Done(:var result):
        _complete(result);
      case [var error, _]:
        // Uncaught error, the isolate exits.
        _complete(_foundSoFar(errors: ['$path: $error']));
      case null:
        // Exited, done already unless it failed.
        _complete(_foundSoFar(errors: ['$path: scan stopped']));
    }
  }

  @override
  void cancel() {
    if (_cancelled || _result.isCompleted) {
      return;
    }
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    _complete(_foundSoFar());
  }

  /// What was found before the scan stopped.
  DartProjectScanResult _foundSoFar({List<String> errors = const []}) {
    var found = _found;
    return DartProjectScanResult(
      path: path,
      projects: found?.projects ?? const [],
      errors: [...?found?.errors, ...errors],
      refreshed: found?.refreshed ?? _started,
      cancelled: _cancelled,
    );
  }

  void _complete(DartProjectScanResult result) {
    if (!_result.isCompleted) {
      _result.complete(result);
      _port.close();
    }
  }
}

/// The scan isolate entry point.
Future<void> _scanMain((SendPort, String, Duration?) args) async {
  var (sendPort, path, progressInterval) = args;
  var result = await DartProjectScanner(
    fileSystemDefault,
    path,
    progressInterval: progressInterval,
    onProgress: (found) => sendPort.send(_Progress(found)),
  ).scan();
  sendPort.send(_Done(result));
}
