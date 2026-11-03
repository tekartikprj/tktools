import 'package:tekartik_prj_tktools/src/host_ci/host_ci_lock.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_model.dart';
import 'package:tekartik_prj_tktools/src/host_ci/host_ci_next.dart';

/// A run as json (`dtk ci --json`, the agent commands of an app).
Map<String, Object?> hostCiRunToJson(DbHostCiRun run) => {
  'id': run.id,
  'project': run.project.v,
  'status': run.runStatus.name,
  if (run.warningSeverity != null) 'severity': run.warningSeverity!.name,
  'trigger': run.trigger.v,
  'client': run.client.v,
  'start': run.startDateTime?.toIso8601String(),
  'end': run.endDateTime?.toIso8601String(),
  'durationMs': run.durationValue?.inMilliseconds,
  'head': run.head.v,
  'branch': run.branch.v,
  'dirty': run.dirty.v,
  'error': run.error.v,
  'validated': run.validatedDateTime?.toIso8601String(),
  'log': run.log.v,
  'steps': [
    for (var step in run.stepList)
      {
        'name': step.name.v,
        'status': step.status.v,
        if (step.policy.v != null) 'policy': step.policy.v,
        if (step.severity.v != null) 'severity': step.severity.v,
        'durationMs': step.duration.v,
        'exitCode': step.exitCode.v,
        'failedPackage': step.failedPackage.v,
        'failedCommand': step.failedCommand.v,
      },
  ],
};

/// A project status as json, [isNext] when it is the next one.
Map<String, Object?> hostCiStatusToJson(
  HostCiProjectStatus status, {
  required bool isNext,
}) {
  var project = status.project;
  return {
    'id': project.id,
    'name': project.name.v,
    'path': project.path.v,
    if (project.root.v != null) 'root': project.root.v,
    if (project.isCloned) 'cloneUrl': project.cloneUrl.v,
    if (project.cloneRef.v != null) 'cloneRef': project.cloneRef.v,
    'skipped': project.isPaused,
    'steps': project.enabledSteps.map((step) => step.name).toList(),
    'options': project.optionsSummary,
    'bucket': status.bucket.name,
    'due': status.isDue,
    'next': isNext,
    'reason': status.reason,
    'running': status.isRunning,
    if (status.git != null)
      'git': {
        'head': status.git!.head,
        'branch': status.git!.branch,
        'dirty': status.git!.dirty,
        'ahead': status.git!.ahead,
      },
    'commitsSince': status.commitsSince,
    'lastRun': status.lastCompletedRun == null
        ? null
        : hostCiRunToJson(status.lastCompletedRun!),
    'openFailures': status.openFailures.map((run) => run.id).toList(),
  };
}

/// The run in progress and the waiting ones of the machine as json.
Map<String, Object?> hostCiQueueStateToJson(HostCiQueueState state) => {
  'running': state.running?.toJson(),
  'waiting': state.waiting.map((entry) => entry.toJson()).toList(),
};
