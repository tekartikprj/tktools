import 'package:tekartik_prj_tktools/src/utils.dart';
import 'package:test/test.dart';

void main() {
  test('findUrlPath', () {
    expect(
      safeGetUrlPath('https://github.com/tekartik/common_utils.dart'),
      '/tekartik/common_utils.dart',
    );
    expect(
      safeGetUrlPath('git@github.com:tekartik/common_utils.dart.git'),
      '/tekartik/common_utils.dart.git',
    );
  });
}
