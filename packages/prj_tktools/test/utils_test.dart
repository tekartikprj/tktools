import 'package:tekartik_prj_tktools/src/utils.dart';
import 'package:test/test.dart';

void main() {
  test('findUrlPath', () {
    expect(safeGetUrlPath('https://github.com/tekartikprj/tkmail'),
        '/tekartikprj/tkmail');
    expect(safeGetUrlPath('git@github.com:tekartikprj/tkmail.git'),
        '/tekartikprj/tkmail.git');
  });
}
