import 'package:args/args.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';

import 'tkpub.dart';
import 'tkpub_add_cmd.dart';

/// Dev flag

/// Clear
class TkpubListCommand extends ShellBinCommand {
  /// Clear
  TkpubListCommand()
      : super(
            name: 'list',
            parser: ArgParser(allowTrailingOptions: true),
            description: '''
      List package dependencies
      ''') {
    parser.addFlag(flagDevKey, help: 'list dev dependencies');
    parser.addFlag(flagOverridesKey, help: 'list dependency overrides');
  }

  @override
  FutureOr<bool> onRun() async {
    var dev = results.flag(flagDevKey);
    var overrides = results.flag(flagOverridesKey);

    var kind = PubDependencyKind.direct;
    if (dev) {
      kind = PubDependencyKind.dev;
      if (overrides) {
        throw ArgumentError(
            'Cannot use --$flagDevKey with --$flagOverridesKey');
      }
    } else if (overrides) {
      kind = PubDependencyKind.override;
    }

    var path = '.';

    var packages = await tkpubDbAction((db) async {
      var packages = await packagesStore.query().getRecords(db.db);
      return packages.map((dbPackage) => dbPackage.id).toList();
    });

    var pubspec = await pathGetPubspecYamlMap(path);

    var dependencies =
        pubspecYamlGetDependenciesPackageName(pubspec, kind: kind);
    packages =
        packages.where((element) => dependencies.contains(element)).toList();
    stdout.writeln('Tkpub $kind packages: ${packages.length}');
    stdout.writeln(packages.join(', '));
    return true;
  }
}
