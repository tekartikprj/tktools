import 'package:tekartik_prj_tktools/yaml_edit.dart';
import 'package:test/test.dart';

void main() {
  group('yaml_edit', () {
    test('updateOrAdd', () {
      var yamlEditor = YamlEditor('test: 1');
      yamlEditor.updateOrAdd(['other'], 2);
      expect(yamlEditor.parseAt([]), {'other': 2, 'test': 1});
      yamlEditor.updateOrAdd(['other', 'sub'], 3);
      expect(yamlEditor.parseAt([]), {
        'other': {'sub': 3},
        'test': 1
      });
      yamlEditor.updateOrAdd(['other', 'other_sub'], 4);
      expect(yamlEditor.parseAt([]), {
        'other': {'other_sub': 4, 'sub': 3},
        'test': 1
      });
      yamlEditor = YamlEditor('test: 1');
      yamlEditor.updateOrAdd(['other', 'sub'], 2);
      expect(yamlEditor.parseAt([]), {
        'other': {'sub': 2},
        'test': 1
      });

      // yamlEditor.update(['YAML'], "YAML Ain't Markup Language");
      // print(yamlEditor);
      // Expected Output:
      // {YAML: YAML Ain't Markup Language}
    });

    test('updateOrAdd null', () {
      var yamlEditor = YamlEditor('test: 1');
      yamlEditor.updateOrAdd(['other'], null);
      expect(yamlEditor.parseAt([]), {'test': 1});
      yamlEditor.updateOrAdd(['other'], []);
      expect(yamlEditor.parseAt([]), {'test': 1});
      yamlEditor.updateOrAdd(['other'], {});
      expect(yamlEditor.parseAt([]), {'test': 1});
      yamlEditor.updateOrAdd(['other', 'sub'], null);
      expect(yamlEditor.parseAt([]), {'test': 1});
    });
  });
}
