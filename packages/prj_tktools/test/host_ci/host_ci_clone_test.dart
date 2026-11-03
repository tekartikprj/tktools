@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tekartik_prj_tktools/host_ci.dart';
import 'package:test/test.dart';

import 'host_ci_test_utils.dart';

/// Real git (the update step), the fake for the rest (run_ci).
class _GitStarter implements HostCiProcessStarter {
  final HostCiFakeProcessStarter fake;
  final _io = HostCiIoProcessStarter();

  _GitStarter(this.fake);

  @override
  Future<HostCiProcess> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) => executable == 'git'
      ? _io.start(executable, arguments, workingDirectory: workingDirectory)
      : fake.start(executable, arguments, workingDirectory: workingDirectory);

  @override
  Future<String?> readFlutterVersion() => fake.readFlutterVersion();
}

void main() {
  test('repository links', () {
    void check(
      String text, {
      required String repoId,
      required String cloneUrl,
      String? ref,
      String? subPath,
    }) {
      var link = hostCiParseRepoLink(text);
      expect(link, isNotNull, reason: text);
      expect(link!.repoId, repoId, reason: text);
      expect(link.cloneUrl, cloneUrl, reason: text);
      expect(link.ref, ref, reason: text);
      expect(link.subPath, subPath, reason: text);
    }

    check(
      'https://github.com/dart-lang/core/tree/main/pkgs/args',
      repoId: 'github.com/dart-lang/core',
      cloneUrl: 'https://github.com/dart-lang/core.git',
      ref: 'main',
      subPath: 'pkgs/args',
    );
    expect(
      hostCiParseRepoLink(
        'https://github.com/dart-lang/core/tree/main/pkgs/args/',
      )!.projectId,
      'github.com/dart-lang/core/pkgs/args',
    );
    check(
      'https://github.com/dart-lang/core/tree/main',
      repoId: 'github.com/dart-lang/core',
      cloneUrl: 'https://github.com/dart-lang/core.git',
      ref: 'main',
    );
    for (var text in [
      'https://github.com/tekartik/sc.dart',
      'https://github.com/tekartik/sc.dart.git',
      'https://github.com/tekartik/sc.dart/',
      'github.com/tekartik/sc.dart',
      'tekartik/sc.dart',
    ]) {
      check(
        text,
        repoId: 'github.com/tekartik/sc.dart',
        cloneUrl: 'https://github.com/tekartik/sc.dart.git',
      );
    }
    check(
      'git@github.com:tekartik/sc.dart.git',
      repoId: 'github.com/tekartik/sc.dart',
      cloneUrl: 'git@github.com:tekartik/sc.dart.git',
    );
    check(
      'https://gitlab.com/group/sub/repo/-/tree/dev/packages/a',
      repoId: 'gitlab.com/group/sub/repo',
      cloneUrl: 'https://gitlab.com/group/sub/repo.git',
      ref: 'dev',
      subPath: 'packages/a',
    );
    for (var text in [
      '',
      'sc.dart',
      '.',
      './a/b',
      '/home/a/b',
      '~/a/b',
      'a/b/c',
      'https://github.com/owner',
    ]) {
      expect(hostCiParseRepoLink(text), isNull, reason: text);
    }
  });

  group('clone', () {
    late Directory topDir;
    late String originPath;
    late HostCi hostCi;
    late HostCiFakeProcessStarter fake;

    setUp(() async {
      topDir = newTempDir('clone');
      // The "remote": a repository with a package in pkgs/args.
      originPath = p.join(topDir.path, 'origin');
      await createGitRepo(originPath);
      File(p.join(originPath, 'pkgs', 'args', 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: args\n');
      await git(originPath, ['add', '.']);
      await git(originPath, ['commit', '-q', '-m', 'args']);
      fake = fakeStarter();
      hostCi = await openTestHostCi(
        p.join(topDir.path, 'host_ci'),
        starter: _GitStarter(fake),
      );
    });

    tearDown(() async {
      await hostCi.close();
      deleteDir(topDir);
    });

    /// A link to the origin (file url: a shallow clone works).
    HostCiRepoLink link({String? subPath}) => HostCiRepoLink(
      repoId: 'example.com/owner/core',
      cloneUrl: Uri.file(originPath).toString(),
      ref: 'main',
      subPath: subPath,
    );

    test('a sub folder: cloned, updated at each run', () async {
      var project = await hostCi.addClone(link(subPath: 'pkgs/args'));
      var root = p.join(
        await hostCi.getCheckoutsDir(),
        'example.com',
        'owner',
        'core',
      );
      expect(project.id, 'example.com/owner/core/pkgs/args');
      expect(project.shortId, 'owner/core/pkgs/args');
      expect(project.name.v, 'args');
      expect(project.path.v, p.join(root, 'pkgs', 'args'));
      expect(project.root.v, root);
      expect(project.isCloned, isTrue);
      expect(project.cloneRef.v, 'main');
      expect(project.enabledSteps.first, HostCiStepName.update);
      expect(
        hostCiStepCommand(project, HostCiStepName.update),
        contains('git fetch --depth 1 origin main'),
      );

      var run = await hostCi.run(project.id, trigger: HostCiTrigger.manual);
      expect(run.runStatus, HostCiRunStatus.success, reason: run.error.v);
      expect(run.stepList.first.stepName, HostCiStepName.update);
      expect(run.stepList.first.stepStatus, HostCiStepStatus.success);
      expect(run.head.v, await git(originPath, ['rev-parse', 'HEAD']));
      // The run_ci steps in the sub folder.
      expect(
        fake.starts
            .where((start) => stepOfArguments(start.arguments) != null)
            .map((start) => start.workingDirectory)
            .toSet(),
        {p.join(root, 'pkgs', 'args')},
      );

      // A new commit upstream: not seen until the next run (no fetch to
      // know), the update brings it.
      var head = await commit(originPath, 'upstream change');
      var status = (await hostCi.getProjects())[project.id]!;
      expect(status.bucket, HostCiBucket.fresh);
      // Something left in the clone by a run goes away.
      File(p.join(root, 'pkgs', 'args', 'left.txt')).writeAsStringSync('x');
      run = await hostCi.run(project.id, trigger: HostCiTrigger.manual);
      expect(run.runStatus, HostCiRunStatus.success, reason: run.error.v);
      expect(run.head.v, head);
      expect(
        File(p.join(root, 'pkgs', 'args', 'left.txt')).existsSync(),
        isFalse,
      );
      var log = await hostCi.readLog(run);
      expect(
        log.map((line) => line.text),
        contains(
          startsWith(
            '# example.com/owner/core/pkgs/args updated to ${head.substring(0, 7)}',
          ),
        ),
      );

      // The Markdown report says where it comes from.
      var markdown = await hostCiRunMarkdown(hostCi, run);
      expect(markdown, contains('- Cloned from: ${link().cloneUrl} (main)'));

      // The whole repository: the same clone.
      var whole = await hostCi.addClone(link());
      expect(whole.id, 'example.com/owner/core');
      expect(whole.path.v, root);
      expect(whole.root.v, isNull);

      // Removed: the clone stays while another project uses it.
      await hostCi.purgeDeletedProject(
        (await hostCi.removeProject(project.id))!,
      );
      expect(Directory(root).existsSync(), isTrue);
      await hostCi.purgeDeletedProject((await hostCi.removeProject(whole.id))!);
      expect(Directory(root).existsSync(), isFalse);
    });

    test('unknown sub folder, failing update', () async {
      await expectLater(
        hostCi.addClone(link(subPath: 'pkgs/nope')),
        throwsA(isA<StateError>()),
      );
      var project = await hostCi.addClone(link());
      // The remote is gone: the update fails, the next steps are skipped.
      deleteDir(Directory(originPath));
      var run = await hostCi.run(project.id, trigger: HostCiTrigger.manual);
      expect(run.runStatus, HostCiRunStatus.failure);
      var update = run.stepList.first;
      expect(update.stepStatus, HostCiStepStatus.failure);
      expect(update.failedCommand.v, startsWith('git fetch'));
      expect(run.stepList.skip(1).map((step) => step.stepStatus).toSet(), {
        HostCiStepStatus.skipped,
      });
    });

    test('checkouts: size, clear, cloned again, moved', () async {
      var project = await hostCi.addClone(link(subPath: 'pkgs/args'));
      var root = project.gitRoot;
      // A clone left by no project.
      var orphan = p.join(
        await hostCi.getCheckoutsDir(),
        'example.com',
        'x',
        'y',
      );
      await createGitRepo(orphan);

      var checkouts = await hostCi.getCheckouts();
      expect(checkouts.map((checkout) => checkout.name), [
        'example.com/owner/core',
        'example.com/x/y',
      ]);
      expect(checkouts.first.path, root);
      expect(checkouts.first.exists, isTrue);
      expect(checkouts.first.size, greaterThan(0));
      expect(checkouts.first.projects.single.id, project.id);
      expect(checkouts.last.projects, isEmpty);
      expect(hostCiFormatSize(1536), '1.5 KB');

      // Cleared: the project stays, its next full run clones it again.
      expect(await hostCi.clearCheckouts([root, orphan]), [root, orphan]);
      expect(Directory(root).existsSync(), isFalse);
      expect(Directory(orphan).existsSync(), isFalse);
      checkouts = await hostCi.getCheckouts();
      expect(checkouts.single.exists, isFalse);
      expect(checkouts.single.size, isNull);
      // A retry without the update step cannot run.
      var retry = await hostCi.run(
        project.id,
        trigger: HostCiTrigger.retry,
        only: [HostCiStepName.analyze],
      );
      expect(retry.runStatus, HostCiRunStatus.error);
      expect(retry.error.v, contains('cleared clone'));
      var run = await hostCi.run(project.id, trigger: HostCiTrigger.manual);
      expect(run.runStatus, HostCiRunStatus.success, reason: run.error.v);
      expect(hostCiIsGitCheckout(root), isTrue);
      expect(() => hostCi.clearCheckouts([topDir.path]), throwsArgumentError);

      // Moved to another folder (the temp one for example): the project
      // points there, cloned there by its next run, the old one deleted.
      var otherDir = p.join(topDir.path, 'other_checkouts');
      await hostCi.setCheckoutsDir(otherDir, deleteOld: true);
      expect(await hostCi.getCheckoutsDir(), otherDir);
      expect(Directory(root).existsSync(), isFalse);
      project = (await hostCi.store.getProject(project.id))!;
      var newRoot = p.join(otherDir, 'example.com', 'owner', 'core');
      expect(project.root.v, newRoot);
      expect(project.path.v, p.join(newRoot, 'pkgs', 'args'));
      run = await hostCi.run(project.id, trigger: HostCiTrigger.manual);
      expect(run.runStatus, HostCiRunStatus.success, reason: run.error.v);
      expect(hostCiIsGitCheckout(newRoot), isTrue);
      // Back to the default: the setting is cleared.
      await hostCi.setCheckoutsDir(null);
      expect(await hostCi.getCheckoutsDir(), hostCi.defaultCheckoutsDir);
      expect((await hostCi.getSettings()).checkoutsDir.v, isNull);
    });
  });
}
