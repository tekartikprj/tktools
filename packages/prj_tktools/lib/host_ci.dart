/// Host CI: the CI of local checkouts run on this machine (pub upgrade,
/// analyze, format, test, build, downgrade analyze), one run at a time, the
/// reports kept until validated or green, a database shared by the
/// `dtk ci` command line and the apps.
library;

export 'src/host_ci/host_ci.dart';
export 'src/host_ci/host_ci_checkouts.dart';
export 'src/host_ci/host_ci_git.dart';
export 'src/host_ci/host_ci_json.dart';
export 'src/host_ci/host_ci_lock.dart';
export 'src/host_ci/host_ci_markdown.dart';
export 'src/host_ci/host_ci_model.dart';
export 'src/host_ci/host_ci_next.dart';
export 'src/host_ci/host_ci_process.dart';
export 'src/host_ci/host_ci_report.dart';
export 'src/host_ci/host_ci_runner.dart';
export 'src/host_ci/host_ci_store.dart';
