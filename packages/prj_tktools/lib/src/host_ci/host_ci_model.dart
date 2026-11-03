import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';

export 'package:tekartik_app_cv_sdb/app_cv_sdb.dart'
    show
        ScvRecordExt,
        ScvRecordToRefExt,
        ScvRecordListExt,
        SdbFactory,
        SdbDatabase;

/// The steps of a run, in the order they run, each one depending on the
/// previous ones: a failing step (with the [HostCiFailurePolicy.fail]
/// policy) skips the following ones.
enum HostCiStepName {
  /// The checkout of a cloned project ([DbHostCiProject.cloneUrl]) brought
  /// to the followed branch: `git fetch --depth 1`, `git reset --hard`,
  /// `git clean -fd` in the clone, run by Host CI itself, first.
  update,

  /// `run_ci --pub-upgrade`, the first step by default.
  pubUpgrade,

  /// `run_ci --pub-get`, the first step instead of [pubUpgrade] when the
  /// project keeps its lock files (`pubGetOnly`).
  pubGet,

  /// `run_ci --analyze`.
  analyze,

  /// `run_ci --format` (check only, exit code 1 on an unformatted file).
  format,

  /// `run_ci --vm-test`: the tests on the host (dart vm, `flutter test`).
  testHost,

  /// `run_ci --test --no-vm-test`: the web tests (chrome dart2js and
  /// dart2wasm, node).
  testWeb,

  /// `run_ci --build`: the web build (`flutter build web`, `webdev build`).
  buildWeb,

  /// The host build of the flutter apps, run by Host CI itself (not
  /// `run_ci`): `flutter build linux`, `macos` or `windows` (`--no-pub`) in
  /// each flutter package having the platform folder and `lib/main.dart`.
  buildHost,

  /// `run_ci --pub-downgrade`: the lowest versions allowed by the
  /// constraints, the lock files are saved before.
  pubDowngrade,

  /// `run_ci --analyze --no-fatal-warnings` on the downgraded dependencies:
  /// errors only, the warnings and the infos of the lowest versions are
  /// reported (the analyze step checks them on the latest ones).
  analyzeDowngrade,

  /// The lock files saved before [pubDowngrade] put back, then
  /// `run_ci --pub-get`: the checkout as it was. Always run after
  /// [pubDowngrade].
  pubRestore,
}

/// The steps a project can turn off, in run order ([HostCiStepName.pubDowngrade]
/// stands for the three downgrade steps).
const hostCiSelectableSteps = [
  HostCiStepName.analyze,
  HostCiStepName.format,
  HostCiStepName.testHost,
  HostCiStepName.testWeb,
  HostCiStepName.buildWeb,
  HostCiStepName.buildHost,
  HostCiStepName.pubDowngrade,
];

/// The steps whose failure policy can be set (the pub steps always fail).
const hostCiPolicySteps = hostCiSelectableSteps;

/// The `run_ci` flag of [HostCiStepName.analyzeDowngrade]: analyze fails on
/// errors only (`run_ci` 1.1.17+3, dropped for an older one).
const hostCiNoFatalWarningsArg = '--no-fatal-warnings';

/// The steps that run together: the downgrade, its analyze and the restore.
const hostCiDowngradeSteps = [
  HostCiStepName.pubDowngrade,
  HostCiStepName.analyzeDowngrade,
  HostCiStepName.pubRestore,
];

/// Label and command line arguments of a step.
extension HostCiStepNameExt on HostCiStepName {
  /// Human readable label.
  String get label => switch (this) {
    HostCiStepName.update => 'update',
    HostCiStepName.pubUpgrade => 'pub upgrade',
    HostCiStepName.pubGet => 'pub get',
    HostCiStepName.analyze => 'analyze',
    HostCiStepName.format => 'format',
    HostCiStepName.testHost => 'test host',
    HostCiStepName.testWeb => 'test web',
    HostCiStepName.buildWeb => 'build web',
    HostCiStepName.buildHost => 'build host',
    HostCiStepName.pubDowngrade => 'pub downgrade',
    HostCiStepName.analyzeDowngrade => 'analyze downgrade',
    HostCiStepName.pubRestore => 'pub restore',
  };

  /// The `run_ci` flag selecting this step, empty for
  /// [HostCiStepName.update] and [HostCiStepName.buildHost] (not `run_ci`
  /// steps).
  String get flag => runCiArguments.isEmpty ? '' : runCiArguments.first;

  /// True for the steps run by `run_ci`, all but [HostCiStepName.update] and
  /// [HostCiStepName.buildHost].
  bool get isRunCi =>
      this != HostCiStepName.update && this != HostCiStepName.buildHost;

  /// The `run_ci` arguments of the step (`--recursive` and the project
  /// arguments excluded), the ones of the GitHub jobs of `tekartik/ci.dart`;
  /// empty for [HostCiStepName.update] and [HostCiStepName.buildHost] (not
  /// `run_ci` steps).
  List<String> get runCiArguments => switch (this) {
    HostCiStepName.update => const [],
    HostCiStepName.pubUpgrade => ['--pub-upgrade'],
    HostCiStepName.pubGet => ['--pub-get'],
    HostCiStepName.analyze => ['--analyze', '--no-pub-get'],
    HostCiStepName.format => ['--format', '--no-pub-get'],
    HostCiStepName.testHost => ['--vm-test', '--no-pub-get'],
    HostCiStepName.testWeb => ['--test', '--no-vm-test', '--no-pub-get'],
    HostCiStepName.buildWeb => ['--build', '--no-pub-get'],
    HostCiStepName.buildHost => const [],
    HostCiStepName.pubDowngrade => ['--pub-downgrade', '--no-override'],
    HostCiStepName.analyzeDowngrade => [
      '--analyze',
      '--no-pub-get',
      '--no-override',
      hostCiNoFatalWarningsArg,
    ],
    HostCiStepName.pubRestore => ['--pub-get', '--no-override'],
  };

  /// True for the steps resolving the dependencies.
  bool get isPub => switch (this) {
    HostCiStepName.pubUpgrade ||
    HostCiStepName.pubGet ||
    HostCiStepName.pubDowngrade ||
    HostCiStepName.pubRestore => true,
    _ => false,
  };

  /// True for the downgrade steps (they run together).
  bool get isDowngrade => hostCiDowngradeSteps.contains(this);

  /// The platform of a test or build step, null for the others.
  HostCiPlatform? get platform => switch (this) {
    HostCiStepName.testHost || HostCiStepName.buildHost => HostCiPlatform.host,
    HostCiStepName.testWeb || HostCiStepName.buildWeb => HostCiPlatform.web,
    _ => null,
  };

  /// The step whose policy applies to this one ([HostCiStepName.pubDowngrade]
  /// for the downgrade analyze), null for the pub steps that always fail.
  HostCiStepName? get policyStep => switch (this) {
    HostCiStepName.analyzeDowngrade => HostCiStepName.pubDowngrade,
    _ when hostCiPolicySteps.contains(this) => this,
    _ => null,
  };
}

/// The value named [name] in [values], null when unknown.
T? _byName<T extends Enum>(List<T> values, String? name) {
  for (var value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return null;
}

/// The step named [name], null when unknown.
HostCiStepName? hostCiStepNameFromName(String? name) =>
    _byName(HostCiStepName.values, name);

/// The step named by [text]: its name (`testWeb`) or its label (`test web`,
/// `test-web`), `downgrade` for [HostCiStepName.pubDowngrade], `get` and
/// `upgrade` for the pub ones; null when unknown (see [hostCiStepNamesParse]
/// for `test` and `build`).
HostCiStepName? hostCiStepNameParse(String text) {
  var lower = text.trim().toLowerCase();
  switch (lower) {
    case 'downgrade':
      return HostCiStepName.pubDowngrade;
    case 'get':
      return HostCiStepName.pubGet;
    case 'upgrade':
      return HostCiStepName.pubUpgrade;
  }
  for (var step in HostCiStepName.values) {
    if (step.name.toLowerCase() == lower ||
        step.label == lower ||
        step.label.replaceAll(' ', '-') == lower ||
        step.label.replaceAll(' ', '_') == lower) {
      return step;
    }
  }
  return null;
}

/// The steps named by [text]: one step ([hostCiStepNameParse]), or a group:
/// `test` (host and web), `build` (web and host); empty when unknown.
List<HostCiStepName> hostCiStepNamesParse(String text) {
  switch (text.trim().toLowerCase()) {
    case 'test':
      return const [HostCiStepName.testHost, HostCiStepName.testWeb];
    case 'build':
      return const [HostCiStepName.buildWeb, HostCiStepName.buildHost];
  }
  var step = hostCiStepNameParse(text);
  return step == null ? const [] : [step];
}

/// [steps] in run order, without duplicates, a downgrade step bringing the
/// three of them.
List<HostCiStepName> hostCiNormalizeSteps(Iterable<HostCiStepName> steps) {
  var set = steps.toSet();
  if (set.any((step) => step.isDowngrade)) {
    set.addAll(hostCiDowngradeSteps);
  }
  return HostCiStepName.values.where(set.contains).toList();
}

/// A run of some steps only: a retry.
enum HostCiPartial {
  /// From a step to the end; green after a red run, it closes the reports
  /// when it starts at (or before) the step that failed.
  from,

  /// Only some steps: never a verdict.
  only,
}

/// The partial named [name], null when unknown (a full run).
HostCiPartial? hostCiPartialFromName(String? name) =>
    _byName(HostCiPartial.values, name);

/// What a failing step does to the run.
enum HostCiFailurePolicy {
  /// The run is red and the following steps are skipped (the default).
  fail,

  /// The run is a warning (with a [HostCiSeverity]), the next steps run.
  warn,

  /// The failure is accepted: the run stays green, the next steps run.
  accept,
}

/// The policy named [name], [HostCiFailurePolicy.fail] when unknown.
HostCiFailurePolicy hostCiFailurePolicyFromName(String? name) =>
    _byName(HostCiFailurePolicy.values, name) ?? HostCiFailurePolicy.fail;

/// How bad a warning is.
enum HostCiSeverity {
  /// Low.
  low,

  /// Medium, the default.
  medium,

  /// High.
  high,
}

/// The severity named [name], [HostCiSeverity.medium] when unknown.
HostCiSeverity hostCiSeverityFromName(String? name) =>
    _byName(HostCiSeverity.values, name) ?? HostCiSeverity.medium;

/// The platforms a project can skip: the test and build steps of the host
/// or of the web.
enum HostCiPlatform {
  /// The host: [HostCiStepName.testHost] and [HostCiStepName.buildHost].
  host,

  /// The web: [HostCiStepName.testWeb] and [HostCiStepName.buildWeb].
  web,
}

/// The platform named [name] (`vm` is the host, `chrome` and `browser` the
/// web), null when unknown.
HostCiPlatform? hostCiPlatformFromName(String? name) {
  var lower = name?.trim().toLowerCase();
  return switch (lower) {
    'vm' => HostCiPlatform.host,
    'chrome' || 'browser' => HostCiPlatform.web,
    _ => _byName(HostCiPlatform.values, lower),
  };
}

/// Status of a run.
enum HostCiRunStatus {
  /// In progress.
  running,

  /// Every executed step succeeded (or failed with an accepted failure).
  success,

  /// At least one step failed with the [HostCiFailurePolicy.fail] policy.
  failure,

  /// Cancelled by the user, what had run before is kept.
  cancelled,

  /// The run could not start (folder gone, `run_ci` not activated, the
  /// process running it died).
  error,

  /// Steps failed with the [HostCiFailurePolicy.warn] policy only.
  warning,
}

/// The status named [name], [HostCiRunStatus.error] when unknown.
HostCiRunStatus hostCiRunStatusFromName(String? name) =>
    _byName(HostCiRunStatus.values, name) ?? HostCiRunStatus.error;

/// Status of one step of a run.
enum HostCiStepStatus {
  /// Not run yet.
  pending,

  /// Running.
  running,

  /// Exit code 0.
  success,

  /// Non zero exit code, or the process could not start (its policy says
  /// whether it fails the run).
  failure,

  /// Not run because an earlier step failed.
  skipped,

  /// Not run (or killed) because the run was cancelled.
  cancelled,
}

/// The status named [name], [HostCiStepStatus.pending] when unknown.
HostCiStepStatus hostCiStepStatusFromName(String? name) =>
    _byName(HostCiStepStatus.values, name) ?? HostCiStepStatus.pending;

/// What started a run.
enum HostCiTrigger {
  /// A given project (a Run button, `dtk ci run <project>`).
  manual,

  /// The next project.
  next,

  /// The due projects, one after the other.
  allDue,

  /// The automatic mode (later).
  auto,

  /// Some steps again (`--step`, `--from`, a step Retry button).
  retry,
}

/// The trigger named [name], [HostCiTrigger.manual] when unknown.
HostCiTrigger hostCiTriggerFromName(String? name) =>
    _byName(HostCiTrigger.values, name) ?? HostCiTrigger.manual;

/// The failure policy of one step of a project.
class DbHostCiStepPolicy extends CvModelBase {
  /// A [HostCiStepName] name (one of [hostCiPolicySteps]).
  final step = CvField<String>('step');

  /// A [HostCiFailurePolicy] name.
  final policy = CvField<String>('policy');

  /// A [HostCiSeverity] name, for [HostCiFailurePolicy.warn].
  final severity = CvField<String>('severity');

  @override
  CvFields get fields => [step, policy, severity];
}

/// A project followed by Host CI, the key is the repository unique name
/// (`github.com/owner/repo`), the canonical path of the checkout when it has
/// no remote.
class DbHostCiProject extends ScvStringRecordBase {
  /// Canonical path of the local checkout, where the run happens.
  final path = CvField<String>('path');

  /// Display name, the repository name.
  final name = CvField<String>('name');

  /// When the project was added, in milliseconds since epoch.
  final added = CvField<int>('added');

  /// A skipped project is kept in the list but never proposed nor run by
  /// "next" or "all due" (a run asked for it still runs).
  final paused = CvField<bool>('paused');

  /// The enabled steps among [hostCiSelectableSteps] (names), every one when
  /// null.
  final steps = CvListField<String>('steps');

  /// `pub get` instead of `pub upgrade` as the first step (the lock files
  /// are kept).
  final pubGetOnly = CvField<bool>('pubGetOnly');

  /// The platforms skipped ([HostCiPlatform] names): their test and build
  /// steps do not run.
  final skipPlatforms = CvListField<String>('skipPlatforms');

  /// The failure policies, [HostCiFailurePolicy.fail] for the steps not
  /// listed.
  final policies = CvModelListField<DbHostCiStepPolicy>('policies');

  /// Extra arguments passed to every `run_ci` call (`-i`...).
  final extraArgs = CvListField<String>('extraArgs');

  /// Key of the last run, null when never run.
  final lastRun = CvField<int>('lastRun');

  /// The git checkout holding [path] when [path] is a sub folder of it
  /// (`pkgs/args` of `dart-lang/core`), null when [path] is the checkout.
  final root = CvField<String>('root');

  /// The remote url of a checkout cloned by Host CI (in its `checkouts`
  /// folder): the [HostCiStepName.update] step runs first, null for a local
  /// checkout.
  final cloneUrl = CvField<String>('cloneUrl');

  /// The branch (or tag) followed by a cloned checkout, null for the default
  /// branch of the remote.
  final cloneRef = CvField<String>('cloneRef');

  @override
  CvFields get fields => [
    path,
    name,
    root,
    cloneUrl,
    cloneRef,
    added,
    paused,
    steps,
    pubGetOnly,
    skipPlatforms,
    policies,
    extraArgs,
    lastRun,
  ];
}

/// Convenient accessors on a project record.
extension DbHostCiProjectExt on DbHostCiProject {
  /// True when skipped.
  bool get isPaused => paused.v ?? false;

  /// True when the first step is `pub get` (not `pub upgrade`).
  bool get isPubGetOnly => pubGetOnly.v ?? false;

  /// True for a checkout cloned by Host CI ([cloneUrl]).
  bool get isCloned => cloneUrl.v != null;

  /// The git checkout: [root], or [path] itself.
  String get gitRoot => root.v ?? path.v ?? '';

  /// The followed ref of a cloned checkout for git (`HEAD`: the default
  /// branch of the remote).
  String get cloneFetchRef => cloneRef.v ?? 'HEAD';

  /// The git commands of the [HostCiStepName.update] step, run in
  /// [gitRoot].
  List<List<String>> get updateGitCommands => [
    ['fetch', '--depth', '1', 'origin', cloneFetchRef],
    ['reset', '--hard', 'FETCH_HEAD'],
    ['clean', '-fd'],
  ];

  /// The selected steps among [hostCiSelectableSteps], in run order (the
  /// names `test` and `build` of the first versions are both of their
  /// steps).
  List<HostCiStepName> get selectedSteps {
    var names = steps.v;
    if (names == null) {
      return hostCiSelectableSteps;
    }
    var selected = {
      for (var name in names)
        ...switch (name) {
          'test' => hostCiStepNamesParse('test'),
          'build' => hostCiStepNamesParse('build'),
          _ => [?hostCiStepNameFromName(name)],
        },
    };
    return hostCiSelectableSteps.where(selected.contains).toList();
  }

  /// The steps a run executes, in run order: the update of a cloned checkout,
  /// the pub step, the selected ones (the skipped platforms out), the
  /// downgrade ones expanded.
  List<HostCiStepName> get enabledSteps {
    var skipped = skippedPlatforms;
    var selected = selectedSteps
        .where((step) => !skipped.contains(step.platform))
        .toList();
    return [
      if (isCloned) HostCiStepName.update,
      if (isPubGetOnly) HostCiStepName.pubGet else HostCiStepName.pubUpgrade,
      for (var step in selected)
        if (step == HostCiStepName.pubDowngrade) ...[
          HostCiStepName.pubDowngrade,
          HostCiStepName.analyzeDowngrade,
          HostCiStepName.pubRestore,
        ] else
          step,
    ];
  }

  /// The skipped platforms.
  List<HostCiPlatform> get skippedPlatforms => [
    for (var platform in HostCiPlatform.values)
      if (skipPlatforms.v?.contains(platform.name) ?? false) platform,
  ];

  /// The policy of [step] ([HostCiFailurePolicy.fail] when not set, always
  /// for the pub steps) and its severity.
  ({HostCiFailurePolicy policy, HostCiSeverity severity}) policyOf(
    HostCiStepName step,
  ) {
    var policyStep = step.policyStep;
    if (policyStep != null) {
      for (var entry in policies.v ?? const <DbHostCiStepPolicy>[]) {
        if (entry.step.v == policyStep.name) {
          return (
            policy: hostCiFailurePolicyFromName(entry.policy.v),
            severity: hostCiSeverityFromName(entry.severity.v),
          );
        }
      }
    }
    return (policy: HostCiFailurePolicy.fail, severity: HostCiSeverity.medium);
  }

  /// Set the policy of [step] (one of [hostCiPolicySteps]),
  /// [HostCiFailurePolicy.fail] removes it.
  void setPolicy(
    HostCiStepName step,
    HostCiFailurePolicy policy, {
    HostCiSeverity? severity,
  }) {
    var policyStep = step.policyStep;
    if (policyStep == null) {
      throw ArgumentError('${step.label} always fails the run');
    }
    var list = [
      for (var entry in policies.v ?? const <DbHostCiStepPolicy>[])
        if (entry.step.v != policyStep.name) entry,
    ];
    if (policy != HostCiFailurePolicy.fail) {
      list.add(
        DbHostCiStepPolicy()
          ..step.v = policyStep.name
          ..policy.v = policy.name
          ..severity.v = policy == HostCiFailurePolicy.warn
              ? (severity ?? HostCiSeverity.medium).name
              : null,
      );
      list.sort(
        (a, b) => (hostCiStepNameFromName(a.step.v)?.index ?? 0).compareTo(
          hostCiStepNameFromName(b.step.v)?.index ?? 0,
        ),
      );
    }
    if (list.isEmpty) {
      policies.clear();
    } else {
      policies.v = list;
    }
  }

  /// When the project was added.
  DateTime? get addedDateTime => _dateTime(added.v);

  /// The id without its host (`owner/repo`, `owner/repo/pkgs/args` for a sub
  /// folder), the last two parts of a path id, the id itself otherwise.
  String get shortId {
    var parts = id.split('/');
    if (parts.length >= 3 && parts.first.contains('.')) {
      return parts.sublist(1).join('/');
    }
    return parts.length >= 3 ? parts.sublist(parts.length - 2).join('/') : id;
  }

  /// The options in one line (empty when all default): `pub get only, no
  /// build host, skip web, build web: warn (medium)`.
  String get optionsSummary {
    var selected = selectedSteps;
    return [
      if (isPubGetOnly) 'pub get only',
      for (var step in hostCiSelectableSteps)
        if (!selected.contains(step) &&
            !skippedPlatforms.contains(step.platform))
          'no ${step == HostCiStepName.pubDowngrade ? 'downgrade' : step.label}',
      for (var platform in skippedPlatforms) 'skip ${platform.name}',
      for (var entry in policies.v ?? const <DbHostCiStepPolicy>[])
        _policyText(entry),
      if (extraArgs.v?.isNotEmpty ?? false) extraArgs.v!.join(' '),
    ].join(', ');
  }
}

String _policyText(DbHostCiStepPolicy entry) {
  var step = hostCiStepNameFromName(entry.step.v)?.label ?? entry.step.v;
  var severity = entry.severity.v == null ? '' : ' (${entry.severity.v})';
  return '$step: ${entry.policy.v}$severity';
}

/// One step of a run.
class DbHostCiStep extends CvModelBase {
  /// A [HostCiStepName] name.
  final name = CvField<String>('name');

  /// A [HostCiStepStatus] name.
  final status = CvField<String>('status');

  /// The [HostCiFailurePolicy] name at run time, null for fail.
  final policy = CvField<String>('policy');

  /// The [HostCiSeverity] name of a warn policy.
  final severity = CvField<String>('severity');

  /// Exit code of the process, null when not run (or not started).
  final exitCode = CvField<int>('exitCode');

  /// Start time, in milliseconds since epoch.
  final start = CvField<int>('start');

  /// How long the step took, in milliseconds.
  final duration = CvField<int>('duration');

  /// The package that failed first (a hint, not a verdict).
  final failedPackage = CvField<String>('failedPackage');

  /// The command that failed first.
  final failedCommand = CvField<String>('failedCommand');

  @override
  CvFields get fields => [
    name,
    status,
    policy,
    severity,
    exitCode,
    start,
    duration,
    failedPackage,
    failedCommand,
  ];
}

/// Convenient accessors on a step record.
extension DbHostCiStepExt on DbHostCiStep {
  /// The step.
  HostCiStepName? get stepName => hostCiStepNameFromName(name.v);

  /// The step to run again for this one: [stepName], the first step of the
  /// `test` and `build` steps of the first versions (test host, build web).
  HostCiStepName? get retryStepName =>
      stepName ??
      switch (name.v) {
        'test' => HostCiStepName.testHost,
        'build' => HostCiStepName.buildWeb,
        _ => null,
      };

  /// The status.
  HostCiStepStatus get stepStatus => hostCiStepStatusFromName(status.v);

  /// The failure policy.
  HostCiFailurePolicy get failurePolicy =>
      hostCiFailurePolicyFromName(policy.v);

  /// The severity of a warning.
  HostCiSeverity get severityValue => hostCiSeverityFromName(severity.v);

  /// True when the step failed.
  bool get isFailed => stepStatus == HostCiStepStatus.failure;

  /// True when the step failed and fails the run.
  bool get isBlockingFailure =>
      isFailed && failurePolicy == HostCiFailurePolicy.fail;

  /// True when the step failed with a warn policy.
  bool get isWarning => isFailed && failurePolicy == HostCiFailurePolicy.warn;

  /// True when the step failed with an accepted failure.
  bool get isAcceptedFailure =>
      isFailed && failurePolicy == HostCiFailurePolicy.accept;

  /// Human readable label of the step.
  String get label => stepName?.label ?? (name.v ?? '?');

  /// The status as a word: `success`, `failure`, `warning (medium)`,
  /// `accepted`, `skipped`...
  String get statusLabel => isWarning
      ? 'warning (${severityValue.name})'
      : isAcceptedFailure
      ? 'accepted'
      : stepStatus.name;

  /// How long the step took, null when not run.
  Duration? get durationValue =>
      duration.v == null ? null : Duration(milliseconds: duration.v!);
}

/// One run of a project, the key is generated.
class DbHostCiRun extends ScvIntRecordBase {
  /// Project id.
  final project = CvField<String>('project');

  /// Checkout path at run time.
  final path = CvField<String>('path');

  /// A [HostCiTrigger] name.
  final trigger = CvField<String>('trigger');

  /// A [HostCiPartial] name for a run of some steps only (a retry), null for
  /// a full run.
  final partial = CvField<String>('partial');

  /// Who ran it (`dtk ci`, an app name).
  final client = CvField<String>('client');

  /// Process id of the process running it.
  final pid = CvField<int>('pid');

  /// Start time, in milliseconds since epoch.
  final start = CvField<int>('start');

  /// End time, in milliseconds since epoch, null while running.
  final end = CvField<int>('end');

  /// A [HostCiRunStatus] name.
  final status = CvField<String>('status');

  /// Why the run is in [HostCiRunStatus.error].
  final error = CvField<String>('error');

  /// When a red (or warning) run was validated (read and accepted by the
  /// user), in milliseconds since epoch: its report is no longer kept open.
  final validated = CvField<int>('validated');

  /// HEAD sha at run time.
  final head = CvField<String>('head');

  /// Branch name at run time.
  final branch = CvField<String>('branch');

  /// Commit time of HEAD, in milliseconds since epoch.
  final commitTime = CvField<int>('commitTime');

  /// Number of modified files (`git status --porcelain` lines), 0 when clean.
  final dirty = CvField<int>('dirty');

  /// Commits ahead of the upstream, null without upstream.
  final ahead = CvField<int>('ahead');

  /// Commits behind the upstream, only known when fetched before the run.
  final behind = CvField<int>('behind');

  /// Dart SDK version.
  final dartVersion = CvField<String>('dartVersion');

  /// Flutter version.
  final flutterVersion = CvField<String>('flutterVersion');

  /// `dev_build` (run_ci) version.
  final runCiVersion = CvField<String>('runCiVersion');

  /// The steps, in run order.
  final steps = CvModelListField<DbHostCiStep>('steps');

  /// Path of the log file, relative to the logs folder, null when the file
  /// was removed by the retention.
  final log = CvField<String>('log');

  /// Refreshed while running, in milliseconds since epoch.
  final heartbeat = CvField<int>('heartbeat');

  @override
  CvFields get fields => [
    project,
    path,
    trigger,
    partial,
    client,
    pid,
    start,
    end,
    status,
    error,
    validated,
    head,
    branch,
    commitTime,
    dirty,
    ahead,
    behind,
    dartVersion,
    flutterVersion,
    runCiVersion,
    steps,
    log,
    heartbeat,
  ];
}

/// Convenient accessors on a run record.
extension DbHostCiRunExt on DbHostCiRun {
  /// The status.
  HostCiRunStatus get runStatus => hostCiRunStatusFromName(status.v);

  /// True while running.
  bool get isRunning => runStatus == HostCiRunStatus.running;

  /// How partial the run is, null for a full run.
  HostCiPartial? get partialValue => hostCiPartialFromName(partial.v);

  /// The first step run (the one a partial run starts from), null when none.
  HostCiStepName? get firstStepName => stepList.firstOrNull?.stepName;

  /// True when the run ended with a verdict (success, warning or failure).
  bool get isCompleted =>
      runStatus == HostCiRunStatus.success ||
      runStatus == HostCiRunStatus.failure ||
      runStatus == HostCiRunStatus.warning;

  /// True when red (failure or error).
  bool get isRed =>
      runStatus == HostCiRunStatus.failure ||
      runStatus == HostCiRunStatus.error;

  /// True when a warning.
  bool get isWarning => runStatus == HostCiRunStatus.warning;

  /// True when green.
  bool get isGreen => runStatus == HostCiRunStatus.success;

  /// True when the report of a red or warning run was validated.
  bool get isValidated => validated.v != null;

  /// True when the process running it died (or was closed) mid-run.
  bool get isInterrupted =>
      runStatus == HostCiRunStatus.error && error.v == hostCiInterruptedError;

  /// The report of a red or warning run, kept until validated or greened (an
  /// interrupted run is not a report).
  bool get isFailureReport => (isRed && !isInterrupted) || isWarning;

  /// The highest severity of the warnings, null when none.
  HostCiSeverity? get warningSeverity {
    HostCiSeverity? severity;
    for (var step in stepList) {
      if (step.isWarning &&
          (severity == null || step.severityValue.index > severity.index)) {
        severity = step.severityValue;
      }
    }
    return severity;
  }

  /// Start time.
  DateTime? get startDateTime => _dateTime(start.v);

  /// End time, null while running.
  DateTime? get endDateTime => _dateTime(end.v);

  /// When validated.
  DateTime? get validatedDateTime => _dateTime(validated.v);

  /// How long the run took, so far while running.
  Duration? get durationValue {
    var startMs = start.v;
    if (startMs == null) {
      return null;
    }
    var endMs = end.v ?? DateTime.now().millisecondsSinceEpoch;
    return Duration(milliseconds: endMs - startMs);
  }

  /// The steps, never null.
  List<DbHostCiStep> get stepList => steps.v ?? const [];

  /// The first step that failed the run, else the first warning, null when
  /// none.
  DbHostCiStep? get failedStep {
    for (var step in stepList) {
      if (step.isBlockingFailure) {
        return step;
      }
    }
    for (var step in stepList) {
      if (step.isWarning) {
        return step;
      }
    }
    return null;
  }

  /// The running step, null when none.
  DbHostCiStep? get runningStep {
    for (var step in stepList) {
      if (step.stepStatus == HostCiStepStatus.running) {
        return step;
      }
    }
    return null;
  }

  /// Short sha (7 characters), empty when unknown.
  String get shortHead {
    var sha = head.v ?? '';
    return sha.length > 7 ? sha.substring(0, 7) : sha;
  }

  /// True when the tree had modified files.
  bool get isDirty => (dirty.v ?? 0) > 0;
}

/// The error of a run whose process died (or was closed) mid-run.
const hostCiInterruptedError = 'interrupted';

/// The settings, one record ([hostCiSettingsKey]).
class DbHostCiSettings extends ScvStringRecordBase {
  /// A green run older than that is proposed again, in days.
  final staleAfterDays = CvField<int>('staleAfterDays');

  /// How many runs per project keep their log file (the open failure
  /// reports always keep theirs).
  final logsKept = CvField<int>('logsKept');

  /// `git fetch` before reading the git facts.
  final fetchBeforeRun = CvField<bool>('fetchBeforeRun');

  /// The repositories hidden from the candidates (their ids).
  final hiddenRepos = CvListField<String>('hiddenRepos');

  /// Where the repositories followed from a link are cloned, the
  /// `checkouts` folder of Host CI when null.
  final checkoutsDir = CvField<String>('checkoutsDir');

  @override
  CvFields get fields => [
    staleAfterDays,
    logsKept,
    fetchBeforeRun,
    hiddenRepos,
    checkoutsDir,
  ];
}

/// Default [DbHostCiSettings.staleAfterDays].
const hostCiDefaultStaleAfterDays = 7;

/// Default [DbHostCiSettings.logsKept].
const hostCiDefaultLogsKept = 10;

/// Settings with their defaults.
extension DbHostCiSettingsExt on DbHostCiSettings {
  /// A green run older than that is proposed again.
  Duration get staleAfter =>
      Duration(days: staleAfterDays.v ?? hostCiDefaultStaleAfterDays);

  /// How many runs per project keep their log file.
  int get logsKeptValue => logsKept.v ?? hostCiDefaultLogsKept;

  /// `git fetch` before reading the git facts.
  bool get fetchBeforeRunValue => fetchBeforeRun.v ?? false;

  /// The repositories hidden from the candidates.
  Set<String> get hiddenRepoSet => (hiddenRepos.v ?? const []).toSet();
}

/// The projects, the key is the repository unique name.
final hostCiProjectStore = scvStringStoreFactory.store<DbHostCiProject>(
  'project',
);

/// The runs, the key is generated (increasing with time).
final hostCiRunStore = scvIntStoreFactory.store<DbHostCiRun>('run');

/// Index on [DbHostCiRun.project].
final hostCiRunProjectIndex = hostCiRunStore.index<String>('project_idx');

/// Index on [DbHostCiRun.start], the latest run is its last record.
final hostCiRunStartIndex = hostCiRunStore.index<int>('start_idx');

/// The settings store, one record.
final hostCiSettingsStore = scvStringStoreFactory.store<DbHostCiSettings>(
  'settings',
);

/// Key of the settings record.
const hostCiSettingsKey = 'settings';

final _runModel = DbHostCiRun();

/// Host CI database schema.
final hostCiSchema = SdbDatabaseSchema(
  stores: [
    hostCiProjectStore.schema(),
    hostCiRunStore.schema(
      autoIncrement: true,
      indexes: [
        hostCiRunProjectIndex.schema(keyPath: _runModel.project.name),
        hostCiRunStartIndex.schema(keyPath: _runModel.start.name),
      ],
    ),
    hostCiSettingsStore.schema(),
  ],
);

/// Current database version.
const hostCiDbVersion = 1;

/// Register the cv constructors of the Host CI models.
void initCvHostCi() {
  cvAddConstructors([
    DbHostCiProject.new,
    DbHostCiRun.new,
    DbHostCiStep.new,
    DbHostCiStepPolicy.new,
    DbHostCiSettings.new,
  ]);
}

DateTime? _dateTime(int? milliseconds) => milliseconds == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(milliseconds);

/// How long ago [time] was, short: `just now`, `5 min ago`, `3 h ago`,
/// `2 days ago`.
String hostCiTimeAgo(DateTime time, {DateTime? now}) {
  var elapsed = (now ?? DateTime.now()).difference(time);
  if (elapsed.inMinutes < 1) {
    return 'just now';
  }
  if (elapsed.inHours < 1) {
    return '${elapsed.inMinutes} min ago';
  }
  if (elapsed.inDays < 1) {
    return '${elapsed.inHours} h ago';
  }
  var days = elapsed.inDays;
  return '$days day${days > 1 ? 's' : ''} ago';
}

/// A duration as `m:ss` (`1:02:03` above an hour).
String hostCiFormatDuration(Duration duration) {
  var seconds = duration.inSeconds;
  var hours = seconds ~/ 3600;
  var minutes = (seconds % 3600) ~/ 60;
  var secs = seconds % 60;
  String pad(int value) => value.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${pad(minutes)}:${pad(secs)}'
      : '$minutes:${pad(secs)}';
}

/// The project matching [query] among [projects]: its id, the end of its id
/// (`owner/repo`, `repo`), its name, or the only id containing it (case
/// insensitive); null when none (or ambiguous).
DbHostCiProject? hostCiFindProject(
  Iterable<DbHostCiProject> projects,
  String query,
) {
  var text = query.trim();
  if (text.isEmpty) {
    return null;
  }
  var list = projects.toList();
  for (var project in list) {
    if (project.id == text) {
      return project;
    }
  }
  var lower = text.toLowerCase();
  var suffix = list
      .where(
        (project) =>
            project.id.toLowerCase().endsWith('/$lower') ||
            project.name.v?.toLowerCase() == lower,
      )
      .toList();
  if (suffix.length == 1) {
    return suffix.single;
  }
  var contains = list
      .where((project) => project.id.toLowerCase().contains(lower))
      .toList();
  return contains.length == 1 ? contains.single : null;
}

/// The steps of a run in one line: `pub upgrade success 0:41, analyze failure
/// 0:12 in ./app (dart analyze), format skipped`.
String hostCiStepsSummary(DbHostCiRun run) => run.stepList
    .map((step) {
      var duration = step.durationValue;
      var failed = step.isFailed;
      return [
        step.label,
        step.statusLabel,
        if (duration != null && step.stepStatus != HostCiStepStatus.pending)
          hostCiFormatDuration(duration),
        if (failed && step.failedPackage.v != null)
          'in ${step.failedPackage.v}',
        if (failed && step.failedCommand.v != null) '(${step.failedCommand.v})',
      ].join(' ');
    })
    .join(', ');

/// The status of a run as a word: `green`, `red`, `warning`, `running`,
/// `cancelled`, `error`.
String hostCiRunStatusLabel(HostCiRunStatus status) => switch (status) {
  HostCiRunStatus.running => 'running',
  HostCiRunStatus.success => 'green',
  HostCiRunStatus.failure => 'red',
  HostCiRunStatus.warning => 'warning',
  HostCiRunStatus.cancelled => 'cancelled',
  HostCiRunStatus.error => 'error',
};

/// The status of [run] as words: `warning (high)` for a warning, `validated`
/// appended to a validated report.
String hostCiRunStatusText(DbHostCiRun run) {
  var severity = run.warningSeverity;
  return [
    hostCiRunStatusLabel(run.runStatus),
    if (run.isWarning && severity != null) '(${severity.name})',
    if (run.isFailureReport && run.isValidated) 'validated',
  ].join(' ');
}

/// A run in one line: `<project> · green · 2 h ago · 3:40 · f2e1a9c · clean`
/// (`started 1 min ago` while running).
String hostCiRunSummary(
  DbHostCiRun run, {
  required String projectName,
  DateTime? now,
}) {
  var end = run.endDateTime;
  var start = run.startDateTime;
  var when = end != null
      ? hostCiTimeAgo(end, now: now)
      : start != null
      ? 'started ${hostCiTimeAgo(start, now: now)}'
      : '';
  var duration = run.durationValue;
  return [
    projectName,
    hostCiRunStatusText(run),
    if (when.isNotEmpty) when,
    if (duration != null) hostCiFormatDuration(duration),
    if (run.shortHead.isNotEmpty) run.shortHead,
    if (run.dirty.v != null)
      if (run.isDirty) 'dirty ${run.dirty.v}' else 'clean',
    if ((run.ahead.v ?? 0) > 0) '↑${run.ahead.v} ahead',
    if (run.error.v != null) run.error.v!,
  ].join(' · ');
}

/// The verdicts of the runs of a project ([runs] the oldest first).
class HostCiVerdicts {
  /// The last run with a verdict (or an error), null when none: the buckets
  /// are computed from it.
  final DbHostCiRun? last;

  /// The failure reports kept open: the red and warning runs after the last
  /// green verdict, not validated, the oldest first.
  final List<DbHostCiRun> open;

  HostCiVerdicts._(this.last, this.open);

  /// The verdicts of [runs], the oldest first.
  ///
  /// A full run that ended (success, warning, failure, an error other than
  /// interrupted) is a verdict; a cancelled or interrupted one is not. A
  /// partial run ([HostCiPartial.only]) is never a verdict, a green re-run
  /// from a step ([HostCiPartial.from]) after a red (or warning) verdict is
  /// one when it starts at or before the first step that failed since the
  /// last green verdict: it then closes the reports.
  factory HostCiVerdicts(List<DbHostCiRun> runs) {
    DbHostCiRun? last;
    var open = <DbHostCiRun>[];
    var sinceGreen = <DbHostCiRun>[];
    for (var run in runs) {
      var partial = run.partialValue;
      if (partial == HostCiPartial.only) {
        continue;
      }
      if (partial == HostCiPartial.from) {
        if (!run.isGreen || sinceGreen.isEmpty) {
          continue;
        }
        var firstFailed = sinceGreen
            .map((red) => red.failedStep?.retryStepName?.index ?? 0)
            .reduce((a, b) => a < b ? a : b);
        var from = run.firstStepName?.index;
        if (from == null || from > firstFailed) {
          continue;
        }
      }
      if (run.isGreen) {
        last = run;
        open.clear();
        sinceGreen.clear();
      } else if (run.isCompleted ||
          (run.runStatus == HostCiRunStatus.error && !run.isInterrupted)) {
        last = run;
        sinceGreen.add(run);
        if (!run.isValidated) {
          open.add(run);
        }
      }
    }
    return HostCiVerdicts._(last, open);
  }
}

/// The open failure reports of a project among its [runs] (oldest first),
/// see [HostCiVerdicts.open].
List<DbHostCiRun> hostCiOpenFailureRuns(List<DbHostCiRun> runs) =>
    HostCiVerdicts(runs).open;
