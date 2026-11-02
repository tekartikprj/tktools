import 'package:tekartik_prj_tktools/tkpub.dart';

/// tkpub
/// tkpub config set cv --git-url https://github.com/tekartik/cv.dart --git-path packages/cv
///  dart run bin/tkpub.dart config set tekartik_common_utils --git-url https://github.com/tekartik/common_utils.dart
Future<void> main(List<String> arguments) async {
  await tkPubMain(arguments);
}
