import 'package:tekartik_prj_tktools/arb.dart';
import 'package:test/test.dart';

Future<void> main() async {
  test('arb_format', () {
    expect(arbSortedKeys(['@', '@@']), ['@@', '@']);
    expect(arbSortedKeys(['@a', 'a']), ['a', '@a']);
    expect(arbSortedKeys(['b', 'a']), ['a', 'b']);
  });
}
