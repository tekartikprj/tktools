import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tekartik_prj_tktools/src/utils.dart';
import 'package:test/test.dart';

/// A directory of a Windows like file system: the parent of the root
/// (`C:\`) is the root itself, nothing exists.
class _WindowsLikeDirectory implements Directory {
  _WindowsLikeDirectory(this.path);

  @override
  final String path;

  @override
  Directory get absolute => this;

  @override
  Directory get parent => _WindowsLikeDirectory(p.windows.dirname(path));

  @override
  bool existsSync() => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  test('findGithubTop stops at a Windows root', () {
    IOOverrides.runZoned(() {
      expect(
        // ignore: deprecated_member_use_from_same_package
        () => findGithubTop(r'C:\Users\me\project'),
        throwsStateError,
      );
    }, createDirectory: _WindowsLikeDirectory.new);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('findGithubTop', () async {
    var top = await Directory.systemTemp.createTemp('prj_tktools_utils');
    try {
      var github = p.join(top.path, 'git', 'github.com');
      var project = p.join(github, 'tekartik', 'repo', 'pkg');
      await Directory(project).create(recursive: true);
      // ignore: deprecated_member_use_from_same_package
      expect(findGithubTop(project), github);
      expect(
        // ignore: deprecated_member_use_from_same_package
        () => findGithubTop(top.path),
        throwsStateError,
      );
    } finally {
      await top.delete(recursive: true);
    }
  });
}
