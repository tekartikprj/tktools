import 'package:dev_build/build_support.dart';
import 'package:fs_shim/utils/io/read_write.dart';
import 'package:path/path.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_common_utils/version_utils.dart';
import 'package:tekartik_prj_tktools/yaml_edit.dart';

/// Bump the version of a package
/// If nothing is specified, it will bump the build or prelease number if present
/// or the patch version if no build or prelease is present.
Future<void> pathVersionBump({
  String? path,
  bool? patch,
  bool? minor,
  bool? major,
  bool? ext,
}) async {
  path ??= '.';
  patch ??= false;
  minor ??= false;
  major ??= false;
  ext ??= false;
  var pubspecYaml = await pathGetPubspecYamlMap(path);
  var version = pubspecYamlGetVersion(pubspecYaml);

  stdout.writeln('Current version: $version');
  version = version.bump(major: major, minor: minor, patch: patch, ext: ext);
  stdout.writeln('New version: $version');
  var file = File(join(path, 'pubspec.yaml'));
  var yaml = await file.readAsString();
  var yamlEditor = YamlEditor(yaml);
  yamlEditor.update(['version'], version.toString());
  await file.writeAsString(stringToIoString(yamlEditor.toString()));
}

/// Bump the version of a package
/// If nothing is specified, it will bump the build or prelease number if present
/// or the patch version if no build or prelease is present.
Future<Version> pathVersionGet({String? path}) async {
  path ??= '.';

  var pubspecYaml = await pathGetPubspecYamlMap(path);
  var version = pubspecYamlGetVersion(pubspecYaml);
  return version;
}

/// Bump the version of a package
/// If nothing is specified, it will bump the build or prelease number if present
/// or the patch version if no build or prelease is present.
Future<void> pathVersionSet({String? path, required Version version}) async {
  path ??= '.';

  var pubspecYaml = await pathGetPubspecYamlMap(path);
  var currentVersion = pubspecYamlGetVersion(pubspecYaml);

  if (currentVersion == version) {
    stdout.writeln('Version is already set to $version');
    return;
  }
  stdout.writeln('Current version: $currentVersion');
  stdout.writeln('New version: $version');
  var file = File(join(path, 'pubspec.yaml'));
  var yaml = await file.readAsString();
  var yamlEditor = YamlEditor(yaml);
  yamlEditor.update(['version'], version.toString());
  await file.writeAsString(stringToIoString(yamlEditor.toString()));
}
