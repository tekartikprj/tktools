import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dev_build/shell.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_registry.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';
import 'package:tekartik_prj_tktools/src/version.dart';

/// Force the dtk git registry export path.
const dtkOptionGitConfigExportPath = 'git-config-export-path';

/// Force the tkpub package registry export path.
const dtkOptionPubConfigExportPath = 'pub-config-export-path';

/// Force the git top.
const dtkOptionGitTop = 'git-top';

const _flagJson = 'json';
const _optionTag = 'tag';
const _optionRepo = 'repo';
const _flagPublished = 'published';
const _flagClone = 'clone';

/// dtk command: read only queries of the dtk git registry and the tkpub
/// package registry, for scripts and agents (`--json`).
class DtkCommand extends ShellBinCommand {
  /// dtk command
  DtkCommand()
    : super(
        name: 'dtk',
        version: packageVersion,
        description:
            'Tekartik repositories and packages: where they are, what they '
            'hold',
      ) {
    parser.addOption(
      dtkOptionGitConfigExportPath,
      help: 'dtk git registry export (default: global prefs)',
    );
    parser.addOption(
      dtkOptionPubConfigExportPath,
      help: 'tkpub package registry export (default: global prefs)',
    );
    parser.addOption(
      dtkOptionGitTop,
      help: 'Git top (default: TEKARTIK_GIT_TOP or the nearest github.com)',
    );
    addCommand(_DtkReposCommand());
    addCommand(_DtkRepoCommand());
    addCommand(_DtkPackagesCommand());
    addCommand(_DtkPackageCommand());
    addCommand(_DtkPathCommand());
    addCommand(_DtkSyncCommand());
  }

  @override
  FutureOr<bool> onRun() => false;
}

abstract class _DtkSubCommand extends ShellBinCommand {
  _DtkSubCommand({
    required super.name,
    required super.description,
    bool withJson = true,
  }) : super(parser: ArgParser(allowTrailingOptions: true)) {
    if (withJson) {
      parser.addFlag(_flagJson, help: 'Json output', negatable: false);
    }
  }

  ArgResults get _top => (parent as DtkCommand).results;

  bool get jsonOutput => results.flag(_flagJson);

  Future<DtkRegistry> loadRegistry({bool requirePackages = false}) =>
      DtkRegistry.load(
        gitTop: _top.option(dtkOptionGitTop),
        gitConfigExportPath: _top.option(dtkOptionGitConfigExportPath),
        pubConfigExportPath: _top.option(dtkOptionPubConfigExportPath),
        requirePackages: requirePackages,
      );

  /// The single trailing argument.
  String singleArg(String what) {
    var rest = results.rest;
    if (rest.length != 1) {
      throw ArgumentError('One argument expected ($what)');
    }
    return rest.first;
  }

  void writeJson(Object? value) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));
  }
}

String _repoLine(DtkRegistryRepo repo) {
  var sb = StringBuffer(repo.id);
  if (repo.tags.isNotEmpty) {
    sb.write('  [${repo.tags.join(', ')}]');
  }
  if (!repo.cloned) {
    sb.write('  (not cloned)');
  }
  if (repo.omit) {
    sb.write('  (omit)');
  }
  return sb.toString();
}

String _packageLine(DtkRegistryPackage package) {
  var sb = StringBuffer(package.name);
  if (package.published) {
    sb.write(' (pub.dev)');
  }
  sb.write('  ${package.path ?? package.gitUrl ?? '?'}');
  if (!package.exists) {
    sb.write('  (not here)');
  }
  return sb.toString();
}

DtkRegistryRepo _findSingleRepo(DtkRegistry registry, String query) {
  var repos = registry.findRepos(query);
  if (repos.isEmpty) {
    throw StateError('Repository not found: $query');
  }
  if (repos.length > 1) {
    throw StateError(
      'Ambiguous repository $query: ${repos.map((repo) => repo.id).join(', ')}',
    );
  }
  return repos.single;
}

class _DtkReposCommand extends _DtkSubCommand {
  _DtkReposCommand()
    : super(name: 'repos', description: 'List the registered repositories') {
    parser.addOption(
      _optionTag,
      help: "Tags expression, e.g. 'public && !flutter'",
    );
  }

  @override
  FutureOr<bool> onRun() async {
    var registry = await loadRegistry();
    var repos = registry.reposWithTags(results.option(_optionTag));
    if (jsonOutput) {
      writeJson(repos.map((repo) => repo.toJson()).toList());
    } else {
      for (var repo in repos) {
        stdout.writeln(_repoLine(repo));
      }
    }
    return true;
  }
}

class _DtkRepoCommand extends _DtkSubCommand {
  _DtkRepoCommand()
    : super(
        name: 'repo',
        description:
            'Show a repository (id, git url, owner/repo, repo, or repo '
            'without .dart)',
      );

  @override
  FutureOr<bool> onRun() async {
    var registry = await loadRegistry();
    var repo = _findSingleRepo(registry, singleArg('repository'));
    if (jsonOutput) {
      writeJson(repo.toJson());
    } else {
      stdout.writeln(_repoLine(repo));
      stdout.writeln('  path: ${repo.path}');
      if (repo.gitUrl != null) {
        stdout.writeln('  git: ${repo.gitUrl}');
      }
      if (repo.packages.isNotEmpty) {
        stdout.writeln('  packages: ${repo.packages.join(', ')}');
      }
    }
    return true;
  }
}

class _DtkPackagesCommand extends _DtkSubCommand {
  _DtkPackagesCommand()
    : super(
        name: 'packages',
        description: 'List the registered (tkpub) packages',
      ) {
    parser.addOption(_optionRepo, help: 'Only the packages of a repository');
    parser.addFlag(
      _flagPublished,
      help: 'Only the packages published on pub.dev',
      negatable: false,
    );
  }

  @override
  FutureOr<bool> onRun() async {
    var registry = await loadRegistry(requirePackages: true);
    var packages = registry.packages;
    var repoQuery = results.option(_optionRepo);
    if (repoQuery != null) {
      packages = registry.packagesInRepo(
        _findSingleRepo(registry, repoQuery).id,
      );
    }
    if (results.flag(_flagPublished)) {
      packages = packages.where((package) => package.published).toList();
    }
    if (jsonOutput) {
      writeJson(packages.map((package) => package.toJson()).toList());
    } else {
      for (var package in packages) {
        stdout.writeln(_packageLine(package));
      }
    }
    return true;
  }
}

class _DtkPackageCommand extends _DtkSubCommand {
  _DtkPackageCommand()
    : super(name: 'package', description: 'Show a registered package');

  @override
  FutureOr<bool> onRun() async {
    var registry = await loadRegistry(requirePackages: true);
    var name = singleArg('package name');
    var package = registry.findPackage(name);
    if (package == null) {
      throw StateError('Package not found: $name');
    }
    if (jsonOutput) {
      writeJson(package.toJson());
    } else {
      stdout.writeln(_packageLine(package));
      if (package.repoId != null) {
        stdout.writeln('  repo: ${package.repoId}');
      }
      stdout.writeln(
        '  git: ${package.gitUrl}'
        '${package.gitPath != null ? ' path: ${package.gitPath}' : ''}',
      );
    }
    return true;
  }
}

class _DtkPathCommand extends _DtkSubCommand {
  _DtkPathCommand()
    : super(
        name: 'path',
        description: 'Local path of a package, else of a repository',
        withJson: false,
      );

  @override
  FutureOr<bool> onRun() async {
    var registry = await loadRegistry();
    var query = singleArg('package or repository');
    String path;
    var package = registry.findPackage(query);
    if (package?.path != null) {
      path = package!.path!;
      if (!package.exists) {
        stderr.writeln('package $query is not on this machine');
      }
    } else {
      var repo = _findSingleRepo(registry, query);
      path = repo.path;
      if (!repo.cloned) {
        stderr.writeln('repository ${repo.id} is not cloned');
      }
    }
    stdout.writeln(path);
    return true;
  }
}

class _DtkSyncCommand extends _DtkSubCommand {
  _DtkSyncCommand()
    : super(
        name: 'sync',
        description:
            'Compare the registry with the git top: missing clones '
            '(--clone clones them) and unregistered checkouts',
      ) {
    parser.addOption(_optionTag, help: 'Only the repositories with these tags');
    parser.addFlag(
      _flagClone,
      help: 'Clone the missing repositories',
      negatable: false,
    );
  }

  @override
  FutureOr<bool> onRun() async {
    var registry = await loadRegistry();
    var missing = registry.missingRepos(tagFilter: results.option(_optionTag));
    var unregistered = registry.unregisteredCheckouts();
    var cloned = <String>[];
    var failed = <String, String>{};
    if (results.flag(_flagClone)) {
      var shell = Shell(verbose: false, throwOnError: false);
      for (var repo in missing) {
        var gitUrl = repo.gitUrl;
        if (gitUrl == null) {
          failed[repo.id] = 'no git url';
          continue;
        }
        if (!jsonOutput) {
          stdout.writeln('cloning ${repo.id}...');
        }
        var result = await shell.runExecutableArguments('git', [
          'clone',
          '-q',
          gitUrl,
          repo.path,
        ]);
        if (result.exitCode == 0) {
          cloned.add(repo.id);
        } else {
          failed[repo.id] = result.stderr.toString().trim();
        }
      }
      missing = missing.where((repo) => !cloned.contains(repo.id)).toList();
    }
    if (jsonOutput) {
      writeJson({
        'gitTop': registry.gitTop,
        'missing': missing.map((repo) => repo.id).toList(),
        'unregistered': unregistered,
        if (results.flag(_flagClone)) 'cloned': cloned,
        if (failed.isNotEmpty) 'failed': failed,
      });
    } else {
      stdout.writeln('git top: ${registry.gitTop}');
      void list(String title, Iterable<String> lines) {
        if (lines.isEmpty) {
          return;
        }
        stdout.writeln('$title (${lines.length}):');
        for (var line in lines) {
          stdout.writeln('  $line');
        }
      }

      list('cloned', cloned);
      list('failed', failed.entries.map((e) => '${e.key}: ${e.value}'));
      list('not cloned', missing.map((repo) => repo.id));
      list('not registered', unregistered);
      if (missing.isEmpty && unregistered.isEmpty && failed.isEmpty) {
        stdout.writeln('in sync');
      }
    }
    if (failed.isNotEmpty) {
      exitCode = 1;
    }
    return true;
  }
}

/// dtk entry point: prints the error and exits with 1 on failure (rethrows in
/// verbose mode).
Future<void> dtkMain(List<String> arguments) async {
  // A closed pipe (`dtk repos | head`) is not an error.
  stdout.done.ignore();
  try {
    await DtkCommand().parseAndRun(arguments);
  } catch (e) {
    var verbose = arguments.contains('-v') || arguments.contains('--verbose');
    if (verbose) {
      rethrow;
    }
    stderr.writeln(switch (e) {
      StateError() => e.message,
      ArgumentError(message: Object message) => message,
      _ => e,
    });
    exit(1);
  }
}
