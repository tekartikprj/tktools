import 'dart:async';
import 'dart:io';

import 'package:path/path.dart';
import 'package:tekartik_app_text/diacritic.dart';
import 'package:tekartik_prj_tktools/src/process_run_import.dart';

//late bool verbose;
/// tkpub command
class TkFindCommand extends ShellBinCommand {
  /// tkpub command
  TkFindCommand() : super(name: 'tkfind') {
    parser.addOption(
      'path',
      abbr: 'p',
      help: 'Path to search',
      defaultsTo: '.',
    );
    parser.addMultiOption('glob', abbr: 'g', help: 'Glob expression');
    parser.addMultiOption('text', abbr: 't', help: 'Text in base name');
    parser.addMultiOption('ext', abbr: 'e', help: 'Text in extension');
    parser.addFlag('file', abbr: 'f', help: 'File only');
    parser.addFlag('dir', abbr: 'd', help: 'Directory only');
    parser.addFlag('hidden', abbr: 'i', help: 'Show hidden files');
  }

  @override
  FutureOr<bool> onRun() async {
    var path = results.option('path') ?? '.';
    var words = results.rest;
    var fileOnly = results.flag('file');
    var dirOnly = results.flag('dir');
    var showHidden = results.flag('hidden');
    var globs = results.multiOption('glob');
    var texts = results.multiOption('text');
    var exts = results.multiOption('ext');
    var finder = Finder(
      path,
      FinderOptions(
        words: words,
        fileOnly: fileOnly,
        dirOnly: dirOnly,
        showHidden: showHidden,
        globs: globs,
        texts: texts,
        exts: exts,
      ),
    );
    await for (var entity in finder.find()) {
      stdout.writeln(finder.entityRelativePath(entity));
    }
    return true;
  }
}

/// Options for the finder
class FinderOptions {
  /// Words to search for
  final List<String> words;

  /// File only
  final bool fileOnly;

  /// Directory only
  final bool dirOnly;

  /// Show hidden files
  final bool showHidden;

  /// Globs to match
  final List<String> globs;

  /// Texts to match in the base name
  final List<String> texts;

  /// Extensions to match
  final List<String> exts;

  /// Constructor for FinderOptions
  FinderOptions({
    required this.words,
    required this.fileOnly,
    required this.dirOnly,
    required this.showHidden,
    required this.globs,
    required this.texts,
    required this.exts,
  });
}

bool _isToBeIgnored(String baseName) {
  if (baseName == '.' || baseName == '..') {
    return true;
  }
  return false;
}

bool _isHidden(String baseName) {
  return baseName.startsWith('.');
}

/// A class that finds files in a directory
class Finder {
  /// The path to search
  final String path;

  /// The options for the finder
  final FinderOptions options;

  /// Returns the relative path of the entity from the base path
  String entityRelativePath(FileSystemEntity entity) {
    return relative(entity.path, from: path);
  }

  /// Returns the absolute path of the entity
  Finder(this.path, this.options);

  /// Find files in the directory
  Stream<FileSystemEntity> find() async* {
    var entities = await Directory(path).list(recursive: false).toList();

    var dirOnly = options.dirOnly;
    var fileOnly = options.fileOnly;
    var showHidden = options.showHidden;
    // ignore: unused_local_variable
    var globs = options.globs
        .map((e) => e.removeDiacritics().toLowerCase().trim())
        .toList();
    var texts = options.texts
        .map((e) => e.removeDiacritics().toLowerCase().trim())
        .toList();
    var exts = options.exts
        .map((e) => e.removeDiacritics().toLowerCase().trim())
        .toList();

    bool matches(FileSystemEntity entity) {
      var entityPath = entity.path;
      if (showHidden || !_isHidden(basename(entityPath))) {
        if (fileOnly && entity is File) {
        } else if (dirOnly && entity is Directory) {
        } else if (!fileOnly && !dirOnly) {
        } else {
          return false;
        }
      } else {
        return false;
      }

      var entityBasename = basename(entity.path).removeDiacritics();
      var ext = extension(entityBasename);
      if (ext.startsWith('.')) {
        ext = ext.substring(1);
      }

      if (texts.isNotEmpty) {
        var basenameWithoutExt = basenameWithoutExtension(entityBasename);

        var found = false;
        for (var text in texts) {
          if (basenameWithoutExt.contains(text)) {
            found = true;
            break;
          }
        }
        if (!found) {
          return false;
        }
      }
      if (exts.isNotEmpty) {
        var found = false;
        for (var extText in exts) {
          if (ext.contains(extText)) {
            found = true;
            break;
          }
        }
        if (!found) {
          return false;
        }
      }
      return true;
    }

    /*
    entities =
        entities
            .where((entity) {
              var entityPath = entity.path;
              if (showHidden || !_isHidden(basename(entityPath))) {
                if (fileOnly && entity is File) {
                  return true;
                } else if (dirOnly && entity is Directory) {
                  return true;
                } else if (!fileOnly && !dirOnly) {
                  return true;
                }
              }

              return false;
            })
            .where((entity) {
              var entityBasename = basename(entity.path).removeDiacritics();
              var ext = extension(entityBasename);
              if (ext.startsWith('.')) {
                ext = ext.substring(1);
              }

              if (texts.isNotEmpty) {
                var basenameWithoutExt = basenameWithoutExtension(
                  entityBasename,
                );

                var found = false;
                for (var text in texts) {
                  if (basenameWithoutExt.contains(text)) {
                    found = true;
                    break;
                  }
                }
                if (!found) {
                  return false;
                }
              }
              if (exts.isNotEmpty) {
                var found = false;
                for (var extText in exts) {
                  if (ext.contains(extText)) {
                    found = true;
                    break;
                  }
                }
                if (!found) {
                  return false;
                }
              }
              return true;
            })
            .toList();*/
    entities.sort((a, b) {
      return a.path.removeDiacritics().toLowerCase().compareTo(
        b.path.removeDiacritics().toLowerCase(),
      );
    });
    for (var entity in entities) {
      // ./test
      // print('entity: ${entity.path}');
      if (_isToBeIgnored(basename(entity.path))) {
        continue;
      }

      if (matches(entity)) {
        yield entity;
      }
      if (entity is Directory) {
        if (showHidden || !_isHidden(basename(entity.path))) {
          // Recursively search in subdirectories
          var subFinder = Finder(entity.path, options);
          await for (var subEntity in subFinder.find()) {
            yield subEntity;
          }
        }
      }
      // yield entity;
    }
    /*

    for (var file in files) {
      if (options.showHidden || !file.path.startsWith('.')) {
        if (options.fileOnly && file is File) {
          yield file.path;
        } else if (options.dirOnly && file is Directory) {
          yield file.path;
        } else if (!options.fileOnly && !options.dirOnly) {
          yield file.path;
        }
      }
    }
    // Implement the find logic here
    // Use options.words, options.fileOnly, options.dirOnly, and options.showHidden
    // to filter the results.*/
  }
}

/// Compat
Future<void> main(List<String> arguments) => tkfindMain(arguments);

/// Direct shell env Path dump run helper for testing.
Future<void> tkfindMain(List<String> arguments) async {
  try {
    await TkFindCommand().parseAndRun(arguments);
  } catch (e) {
    var verbose = arguments.contains('-v') || arguments.contains('--verbose');
    if (verbose) {
      rethrow;
    }
    stderr.writeln(e);
    exit(1);
  }
}
