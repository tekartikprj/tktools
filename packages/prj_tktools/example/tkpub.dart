import 'package:tekartik_prj_tktools/src/bin/tkpub.dart' as tkpub;

/// Example
/// tkpub config set tekartik_script --git-url git@github.com:alextekartik/script.dart --git-path packages/script
///  dart run bin/tkpub.dart config set tekartik_common_utils --git-url https://github.com/tekartik/common_utils.dart
Future<void> main(List<String> arguments) async {
  await tkpub.main(arguments);
}
