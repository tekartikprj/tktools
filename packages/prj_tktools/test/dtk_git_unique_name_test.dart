import 'package:tekartik_prj_tktools/src/dtk/dtk.dart';
import 'package:test/test.dart';

void main() {
  test('dtkGitUniqueNameFromUrl trailing slash', () {
    // A url copied from a browser: `dtk repo sembast` must find it.
    expect(
      dtkGitUniqueNameFromUrl('https://github.com/tekartik/sembast.dart/'),
      'github.com/tekartik/sembast.dart',
    );
    expect(
      dtkGitUniqueNameFromUrl('git@github.com:tekartik/sembast.dart.git/'),
      'github.com/tekartik/sembast.dart',
    );
  });
}
