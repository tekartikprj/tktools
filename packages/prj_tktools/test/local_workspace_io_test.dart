@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart';
import 'package:tekartik_prj_tktools/src/local_workspace.dart';
import 'package:test/test.dart';

void main() {
  late Directory top;
  late String ideaDirPath;

  setUp(() {
    top = Directory.systemTemp.createTempSync('local_workspace_io');
    ideaDirPath = join(top.path, '.idea');
    Directory(ideaDirPath).createSync();
  });
  tearDown(() {
    top.deleteSync(recursive: true);
  });

  group('localWorkspaceIdeaOpenReason', () {
    test('none', () {
      expect(
        localWorkspaceIdeaOpenReason(ideaDirPath, environment: {}),
        isNull,
      );
      File(join(ideaDirPath, 'modules.xml')).writeAsStringSync('');
      File(join(ideaDirPath, 'workspace.xml')).writeAsStringSync('');
      expect(
        localWorkspaceIdeaOpenReason(ideaDirPath, environment: {}),
        isNull,
      );
      expect(
        localWorkspaceIdeaOpenReason(
          ideaDirPath,
          environment: {'TERMINAL_EMULATOR': 'xterm'},
        ),
        isNull,
      );
    });
    test('workspace.xml without modules.xml', () {
      File(join(ideaDirPath, 'workspace.xml')).writeAsStringSync('');
      expect(
        localWorkspaceIdeaOpenReason(ideaDirPath, environment: {}),
        contains('workspace.xml'),
      );
    });
    test('JetBrains terminal', () {
      expect(
        localWorkspaceIdeaOpenReason(
          ideaDirPath,
          environment: {'TERMINAL_EMULATOR': 'JetBrains-JediTerm'},
        ),
        contains('JetBrains'),
      );
    });
  });

  test('localWorkspaceWriteFileIfChanged', () {
    var file = File(join(top.path, 'file.txt'));
    expect(localWorkspaceWriteFileIfChanged(file, 'a'), isTrue);
    expect(localWorkspaceWriteFileIfChanged(file, 'a'), isFalse);
    expect(localWorkspaceWriteFileIfChanged(file, 'b'), isTrue);
    expect(file.readAsStringSync(), 'b');
  });
}
