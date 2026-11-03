import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

/// The in process mutexes, one per lock file (two objects of a process on the
/// same file must exclude each other: a file lock is per process).
final _processLocks = <String, Lock>{};

/// An exclusive lock around the database sessions.
abstract class HostCiLock {
  /// Run [action] holding the lock, waiting for it.
  Future<T> synchronized<T>(Future<T> Function() action);
}

/// A lock within this process only, for a database of this process only (a
/// memory one, in the tests: no file access).
class HostCiMemoryLock implements HostCiLock {
  final _lock = Lock();

  @override
  Future<T> synchronized<T>(Future<T> Function() action) =>
      _lock.synchronized(action);
}

/// An exclusive lock between the processes of this machine (a lock on the
/// file at [path], released by the system when the process dies) and the
/// callers of this process.
///
/// Within a process, never open and close [path] elsewhere while holding it:
/// closing any handle of a file releases the locks the process has on it.
class HostCiFileLock implements HostCiLock {
  /// The lock file.
  final String path;

  /// Creates a lock on [path] (created when missing).
  HostCiFileLock(this.path);

  Lock get _lock => _processLocks[p.normalize(p.absolute(path))] ??= Lock();

  @override
  Future<T> synchronized<T>(Future<T> Function() action) =>
      _lock.synchronized(() async {
        var file = File(path);
        await file.parent.create(recursive: true);
        var raf = await file.open(mode: FileMode.append);
        try {
          await raf.lock(FileLock.blockingExclusive);
          try {
            return await action();
          } finally {
            await raf.unlock();
          }
        } finally {
          await raf.close();
        }
      });
}

/// Try to lock [file] exclusively without waiting: the open handle holding
/// the lock, null when another process holds it (or the file is gone).
Future<RandomAccessFile?> _tryLock(
  File file, {
  int start = 0,
  int end = -1,
}) async {
  RandomAccessFile raf;
  try {
    raf = await file.open(mode: FileMode.append);
  } catch (_) {
    return null;
  }
  try {
    await raf.lock(FileLock.exclusive, start, end);
    return raf;
  } catch (_) {
    await raf.close();
    return null;
  }
}

/// The byte range locked in a ticket, after its content: the content stays
/// readable by the other processes (a Windows lock forbids reading the
/// bytes it covers).
const _ticketLockStart = 1 << 30;
const _ticketLockEnd = _ticketLockStart + 1;

/// A ticket younger than this is alive (not locked yet by its process).
const _ticketGrace = Duration(seconds: 2);

/// A run asked on this machine: waiting its turn in the queue, or running.
class HostCiQueueEntry {
  /// The ticket name (the oldest first), null for the running entry.
  final String? ticket;

  /// Process id.
  final int pid;

  /// The project id.
  final String project;

  /// A `HostCiTrigger` name.
  final String trigger;

  /// Who asked (`dtk ci`, an app name).
  final String? client;

  /// When it was asked (or started for the running entry).
  final DateTime time;

  /// The run key once started.
  final int? runId;

  /// Creates an entry.
  HostCiQueueEntry({
    this.ticket,
    required this.pid,
    required this.project,
    required this.trigger,
    this.client,
    required this.time,
    this.runId,
  });

  /// From the json of a ticket or of the running file, null when invalid.
  static HostCiQueueEntry? fromJson(Object? json, {String? ticket}) {
    if (json is! Map) {
      return null;
    }
    var pid = json['pid'];
    var project = json['project'];
    var time = json['time'];
    if (pid is! int || project is! String || time is! int) {
      return null;
    }
    return HostCiQueueEntry(
      ticket: ticket,
      pid: pid,
      project: project,
      trigger: json['trigger']?.toString() ?? 'manual',
      client: json['client']?.toString(),
      time: DateTime.fromMillisecondsSinceEpoch(time),
      runId: json['runId'] is int ? json['runId'] as int : null,
    );
  }

  /// The json.
  Map<String, Object?> toJson() => {
    'pid': pid,
    'project': project,
    'trigger': trigger,
    if (client != null) 'client': client,
    'time': time.millisecondsSinceEpoch,
    if (runId != null) 'runId': runId,
  };

  /// Copy with the run key.
  HostCiQueueEntry withRunId(int runId) => HostCiQueueEntry(
    ticket: ticket,
    pid: pid,
    project: project,
    trigger: trigger,
    client: client,
    time: time,
    runId: runId,
  );

  @override
  String toString() =>
      '$project ($trigger${client == null ? '' : ', $client'}, pid $pid)';
}

/// The runs of this machine: the running one and the waiting ones.
class HostCiQueueState {
  /// The run in progress, null when none.
  final HostCiQueueEntry? running;

  /// The runs waiting, the oldest first (the next to run).
  final List<HostCiQueueEntry> waiting;

  /// Creates a state.
  const HostCiQueueState({this.running, this.waiting = const []});

  /// True when nothing runs nor waits.
  bool get isEmpty => running == null && waiting.isEmpty;

  @override
  String toString() =>
      'running: ${running ?? '-'}, waiting: ${waiting.join(', ')}';
}

/// Thrown when a wait in the queue is cancelled.
class HostCiQueueCancelledException implements Exception {
  @override
  String toString() => 'cancelled while waiting';
}

/// The run slot held by this process, [release] when done.
class HostCiRunSlot {
  final HostCiRunQueue _queue;
  final RandomAccessFile _raf;

  /// The entry, the run key added once known.
  HostCiQueueEntry entry;

  HostCiRunSlot._(this._queue, this._raf, this.entry);

  /// Record the run key (other processes read it).
  Future<void> setRunId(int runId) async {
    entry = entry.withRunId(runId);
    await _queue._writeRunning(entry);
  }

  /// Give the slot back.
  Future<void> release() => _queue._release(this);
}

/// One run at a time on this machine, the oldest asked first.
///
/// A process wanting to run writes a ticket (a file of the [queueDir] named
/// after the time it asked, locked while the process lives) and waits until
/// its ticket is the oldest live one and the run lock is free. The process
/// holding the run lock describes its run in the running file. A process that
/// dies loses its locks: its ticket and its running file are then ignored.
class HostCiRunQueue {
  /// The Host CI folder.
  final String dir;

  /// How often a waiting process checks the queue.
  final Duration pollInterval;

  /// Creates the queue in [dir].
  HostCiRunQueue(
    this.dir, {
    this.pollInterval = const Duration(milliseconds: 500),
  });

  /// The tickets folder.
  String get queueDir => p.join(dir, 'queue');

  /// The run lock file.
  String get runLockPath => p.join(dir, 'run.lock');

  /// The running file (json), written by the process holding the run lock.
  String get runningPath => p.join(dir, 'running.json');

  /// The slot held by this process (whatever the queue object).
  static final _held = <String, HostCiRunSlot>{};

  /// The tickets of this process, by name. Never opened again while held:
  /// closing any handle of a file releases the locks the process has on it.
  static final _ownTickets = <String, HostCiQueueEntry>{};

  static var _ticketCount = 0;

  String get _key => p.normalize(p.absolute(dir));

  /// The slot held by this process, null when none.
  HostCiRunSlot? get heldSlot => _held[_key];

  /// Wait for the turn of [entry] then take the run slot.
  ///
  /// [onWaiting] is called with the queue while waiting (when it changes),
  /// [cancel] completing stops waiting ([HostCiQueueCancelledException]).
  Future<HostCiRunSlot> acquire(
    HostCiQueueEntry entry, {
    void Function(HostCiQueueState state)? onWaiting,
    Future<void>? cancel,
  }) async {
    if (heldSlot != null) {
      throw StateError('A run is in progress in this process');
    }
    var cancelled = false;
    unawaited(cancel?.then((_) => cancelled = true));
    var time = entry.time;
    var name =
        '${time.microsecondsSinceEpoch.toString().padLeft(20, '0')}'
        '_${pid}_${++_ticketCount}.json';
    var ticketFile = File(p.join(queueDir, name));
    await ticketFile.parent.create(recursive: true);
    // Locked (a range after the content) then written, in place (an open
    // file cannot be renamed on Windows): the other processes see a young
    // ticket as alive until it is locked.
    _ownTickets[name] = HostCiQueueEntry.fromJson(
      entry.toJson(),
      ticket: name,
    )!;
    var ticketRaf = await ticketFile.open(mode: FileMode.write);
    await ticketRaf.lock(FileLock.exclusive, _ticketLockStart, _ticketLockEnd);
    await ticketRaf.writeString(jsonEncode(entry.toJson()));
    await ticketRaf.flush();
    Future<void> dropTicket() async {
      _ownTickets.remove(name);
      try {
        await ticketRaf.close();
      } catch (_) {}
      try {
        await ticketFile.delete();
      } catch (_) {}
    }

    String? lastState;
    try {
      while (true) {
        if (cancelled) {
          throw HostCiQueueCancelledException();
        }
        var tickets = await _liveTickets();
        if (tickets.isNotEmpty && tickets.first.ticket == name) {
          var runRaf = await _tryLock(File(runLockPath));
          if (runRaf != null) {
            var slot = HostCiRunSlot._(this, runRaf, entry);
            _held[_key] = slot;
            await _writeRunning(entry);
            await dropTicket();
            return slot;
          }
        }
        if (onWaiting != null) {
          var state = await readState(tickets: tickets);
          var text = state.toString();
          if (text != lastState) {
            lastState = text;
            onWaiting(state);
          }
        }
        await _sleep(pollInterval, () => cancelled);
      }
    } catch (_) {
      await dropTicket();
      rethrow;
    }
  }

  Future<void> _sleep(Duration duration, bool Function() cancelled) async {
    var end = DateTime.now().add(duration);
    while (!cancelled() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _writeRunning(HostCiQueueEntry entry) async {
    var file = File(runningPath);
    var tmp = File('$runningPath.$pid.tmp');
    await tmp.writeAsString(jsonEncode(entry.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  Future<void> _release(HostCiRunSlot slot) async {
    if (_held[_key] != slot) {
      return;
    }
    _held.remove(_key);
    try {
      await File(runningPath).delete();
    } catch (_) {}
    try {
      await slot._raf.unlock();
    } catch (_) {}
    try {
      await slot._raf.close();
    } catch (_) {}
  }

  /// The live tickets, the oldest first; the tickets of dead processes are
  /// deleted.
  Future<List<HostCiQueueEntry>> _liveTickets() async {
    var dir = Directory(queueDir);
    if (!dir.existsSync()) {
      return const [];
    }
    var names = <String>[];
    try {
      await for (var entity in dir.list(followLinks: false)) {
        var name = p.basename(entity.path);
        if (entity is File && name.endsWith('.json')) {
          names.add(name);
        }
      }
    } catch (_) {
      return const [];
    }
    names.sort();
    var entries = <HostCiQueueEntry>[];
    for (var name in names) {
      var own = _ownTickets[name];
      if (own != null) {
        entries.add(own);
        continue;
      }
      var file = File(p.join(queueDir, name));
      var ownerPid = int.tryParse(name.split('_').elementAtOrNull(1) ?? '');
      // A ticket of this process that is not in the list is a leftover of
      // an earlier process with the same pid; the others are probed, but a
      // young one (maybe not locked yet).
      var young = false;
      try {
        young =
            DateTime.now().difference(file.statSync().modified) < _ticketGrace;
      } catch (_) {}
      var probe = ownerPid == pid || young
          ? null
          : await _tryLock(file, start: _ticketLockStart, end: _ticketLockEnd);
      var dead = ownerPid == pid || probe != null;
      if (probe != null) {
        await probe.unlock();
        await probe.close();
      }
      if (dead) {
        try {
          await file.delete();
        } catch (_) {}
        continue;
      }
      try {
        var entry = HostCiQueueEntry.fromJson(
          jsonDecode(await file.readAsString()),
          ticket: name,
        );
        if (entry != null) {
          entries.add(entry);
        }
      } catch (_) {
        // Being written or deleted.
      }
    }
    return entries;
  }

  /// The run in progress on this machine, null when none (a running file
  /// left by a dead process is ignored).
  Future<HostCiQueueEntry?> readRunning() async {
    var held = heldSlot;
    if (held != null) {
      return held.entry;
    }
    var file = File(runningPath);
    if (!file.existsSync()) {
      return null;
    }
    // Probe the run lock: free means nobody runs.
    var raf = await _tryLock(File(runLockPath));
    if (raf != null) {
      try {
        if (heldSlot == null) {
          await file.delete();
        }
      } catch (_) {
      } finally {
        await raf.unlock();
        await raf.close();
      }
      return null;
    }
    try {
      return HostCiQueueEntry.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }

  /// The run in progress and the waiting ones.
  Future<HostCiQueueState> readState({List<HostCiQueueEntry>? tickets}) async {
    return HostCiQueueState(
      running: await readRunning(),
      waiting: tickets ?? await _liveTickets(),
    );
  }
}
