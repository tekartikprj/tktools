import 'package:tekartik_prj_tktools/src/host_ci/host_ci_git.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_model.dart';

/// Why (or why not) a project is proposed, the first matching bucket wins.
enum HostCiBucket {
  /// Never run, first.
  neverRun,

  /// HEAD or the tree changed since the last completed run.
  changed,

  /// The last run is red, not validated, and nothing changed.
  red,

  /// The last run is green (a warning, a validated red), nothing changed,
  /// but it is older than the stale delay.
  stale,

  /// The last run is green (a warning, a validated red) and recent: not
  /// proposed.
  fresh,

  /// Skipped by the user: never proposed.
  paused,
}

/// Whether the bucket is proposed (part of "run all due").
extension HostCiBucketExt on HostCiBucket {
  /// True when the project should run.
  bool get isDue => switch (this) {
    HostCiBucket.neverRun ||
    HostCiBucket.changed ||
    HostCiBucket.red ||
    HostCiBucket.stale => true,
    HostCiBucket.fresh || HostCiBucket.paused => false,
  };

  /// Display name (`skipped` for [HostCiBucket.paused]).
  String get label => switch (this) {
    HostCiBucket.neverRun => 'never run',
    HostCiBucket.paused => 'skipped',
    _ => name,
  };
}

/// A project with its last run, its git facts and its bucket.
class HostCiProjectStatus {
  /// The project.
  final DbHostCiProject project;

  /// The last run (any status, running included), null when never run.
  final DbHostCiRun? lastRun;

  /// The last run that ended with a verdict (or an error), the one the bucket
  /// is computed from.
  final DbHostCiRun? lastCompletedRun;

  /// The red and warning runs since the last green one, not validated, the
  /// oldest first: the failure reports kept open.
  final List<DbHostCiRun> openFailures;

  /// The git facts of the checkout now, null when it is not a git checkout
  /// (or gone).
  final HostCiGitFacts? git;

  /// Commits since the last completed run, null when unknown.
  final int? commitsSince;

  /// The bucket.
  final HostCiBucket bucket;

  /// Why the project is in its bucket, displayed.
  final String reason;

  /// Creates a status.
  HostCiProjectStatus({
    required this.project,
    required this.lastRun,
    required this.lastCompletedRun,
    this.openFailures = const [],
    required this.git,
    required this.commitsSince,
    required this.bucket,
    required this.reason,
  });

  /// True when the project should run.
  bool get isDue => bucket.isDue;

  /// True while a run of the project is in progress.
  bool get isRunning => lastRun?.isRunning ?? false;

  /// True when the checkout folder is missing.
  bool get isMissing => git == null;

  /// The latest open failure report, null when none.
  DbHostCiRun? get openFailure => openFailures.lastOrNull;

  @override
  String toString() => '${project.id} ${bucket.name}: $reason';
}

/// The projects of Host CI, ordered: the due ones first, in bucket order and
/// the oldest last run first within a bucket, then the fresh greens, the
/// skipped last.
class HostCiProjects {
  /// The statuses, ordered.
  final List<HostCiProjectStatus> statuses;

  /// Creates the list.
  HostCiProjects(this.statuses);

  /// The project to run next, null when nothing is due.
  HostCiProjectStatus? get next {
    for (var status in statuses) {
      if (status.isDue && !status.isRunning && !status.isMissing) {
        return status;
      }
    }
    return null;
  }

  /// The due projects, in order.
  List<HostCiProjectStatus> get due => statuses
      .where((status) => status.isDue && !status.isRunning && !status.isMissing)
      .toList();

  /// The projects with an open failure report, the reds first (then the
  /// warnings by severity), the latest first.
  List<HostCiProjectStatus> get failures {
    var list = statuses.where((status) => status.openFailure != null).toList();
    int rank(DbHostCiRun run) =>
        run.isRed ? 10 : (run.warningSeverity?.index ?? 0);
    list.sort((a, b) {
      var runA = a.openFailure!;
      var runB = b.openFailure!;
      var cmp = rank(runB).compareTo(rank(runA));
      if (cmp != 0) {
        return cmp;
      }
      return (runB.start.v ?? 0).compareTo(runA.start.v ?? 0);
    });
    return list;
  }

  /// The status of a project, null when unknown.
  HostCiProjectStatus? operator [](String projectId) {
    for (var status in statuses) {
      if (status.project.id == projectId) {
        return status;
      }
    }
    return null;
  }

  /// True when no project is listed.
  bool get isEmpty => statuses.isEmpty;
}

/// The bucket and the reason of one project.
///
/// [lastCompletedRun] is the last run with a verdict (a cancelled run does
/// not count), [git] the facts now, [commitsSince] the commits between the
/// last run's HEAD and the current one (null when unknown).
(HostCiBucket, String) hostCiBucketOf({
  required DbHostCiProject project,
  required DbHostCiRun? lastCompletedRun,
  required HostCiGitFacts? git,
  required int? commitsSince,
  required Duration staleAfter,
  required DateTime now,
}) {
  if (project.isPaused) {
    return (HostCiBucket.paused, 'skipped');
  }
  var run = lastCompletedRun;
  if (run == null) {
    return (HostCiBucket.neverRun, 'never run');
  }
  var color = run.runStatus == HostCiRunStatus.error
      ? 'failed'
      : hostCiRunStatusLabel(run.runStatus);
  if (run.isFailureReport && run.isValidated) {
    color = '$color (validated)';
  }
  var ago = run.endDateTime == null
      ? ''
      : hostCiTimeAgo(run.endDateTime!, now: now);
  // A clone only changes at its update step (the remote is not read here):
  // never run, red or stale.
  if (git != null && !project.isCloned) {
    var headChanged = run.head.v != null && run.head.v != git.head;
    var dirtyChanged = (run.dirty.v ?? 0) != git.dirty;
    if (headChanged) {
      var count = commitsSince;
      var what = count == null || count == 0
          ? 'changed'
          : '$count commit${count > 1 ? 's' : ''}';
      return (HostCiBucket.changed, '$what since the $color run of $ago');
    }
    if (dirtyChanged) {
      return (
        HostCiBucket.changed,
        'tree changed since the $color run of $ago',
      );
    }
  }
  if (run.isRed && !run.isValidated) {
    return (HostCiBucket.red, '$color $ago, unchanged');
  }
  var end = run.endDateTime;
  if (end == null || now.difference(end) > staleAfter) {
    return (HostCiBucket.stale, '$color $ago, unchanged');
  }
  return (HostCiBucket.fresh, '$color $ago, unchanged');
}

/// Order the statuses: bucket order, then the oldest started wins within a
/// bucket (the start of the last run, the time added when never run).
List<HostCiProjectStatus> hostCiSortStatuses(
  List<HostCiProjectStatus> statuses,
) {
  var sorted = List<HostCiProjectStatus>.from(statuses);
  sorted.sort((a, b) {
    var cmp = a.bucket.index.compareTo(b.bucket.index);
    if (cmp != 0) {
      return cmp;
    }
    var timeA = a.lastRun?.start.v ?? a.project.added.v ?? 0;
    var timeB = b.lastRun?.start.v ?? b.project.added.v ?? 0;
    cmp = timeA.compareTo(timeB);
    if (cmp != 0) {
      return cmp;
    }
    return a.project.id.compareTo(b.project.id);
  });
  return sorted;
}

/// Order the statuses by their last completed run, the oldest first
/// whatever the bucket (the start of the run the list shows, the never run
/// ones first): the projects not checked for the longest time.
List<HostCiProjectStatus> hostCiSortStatusesByOldestRun(
  List<HostCiProjectStatus> statuses,
) {
  var sorted = List<HostCiProjectStatus>.from(statuses);
  sorted.sort((a, b) {
    var cmp = (a.lastCompletedRun?.start.v ?? 0).compareTo(
      b.lastCompletedRun?.start.v ?? 0,
    );
    if (cmp != 0) {
      return cmp;
    }
    return a.project.id.compareTo(b.project.id);
  });
  return sorted;
}
