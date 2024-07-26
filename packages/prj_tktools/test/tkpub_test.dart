import 'package:tekartik_prj_tktools/src/bin/tkpub_package_info.dart';
import 'package:test/test.dart';

void main() {
  test('TkpubPackageInfo', () {
    expect(
        TkpubPackageInfo.parse('dev:test:{"dummy":"test"}'),
        TkpubPackageInfo(
            target: TkpubTarget.dev, name: 'test', def: {'dummy': 'test'}));
    expect(TkpubPackageInfo.parse('test'), TkpubPackageInfo(name: 'test'));
    expect(TkpubPackageInfo.parse("'test'"), TkpubPackageInfo(name: 'test'));
    expect(TkpubPackageInfo.parse('dev:test'),
        TkpubPackageInfo(target: TkpubTarget.dev, name: 'test'));
  });
}
