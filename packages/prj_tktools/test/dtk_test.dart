import 'package:tekartik_prj_tktools/src/dtk/dtk.dart';
import 'package:test/test.dart';

Future<void> main() async {
  group('dtk', () {
    test('dtkGitUniqueNameFromUrl', () async {
      expect(
        dtkGitUniqueNameFromUrl(
          'git@github.com:tekartik/app_common_utils.dart.git',
        ),
        'github.com/tekartik/app_common_utils.dart',
      );
      expect(
        dtkGitUniqueNameFromUrl(
          'https://github.com/tekartik/app_common_utils.dart',
        ),
        'github.com/tekartik/app_common_utils.dart',
      );
    });
  });
}
