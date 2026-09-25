import 'package:path/path.dart' as p;
import 'package:tekartik_app_text/diacritic.dart';

import 'dart_project.dart';

/// Lower case, diacritics free text, so that typing `elio` finds `Élio`.
String dartProjectSearchNormalize(String text) =>
    text.toLowerCase().removeDiacritics();

/// The [projects] matching [query], the best first.
///
/// [query] is split in words, lower case and diacritics free, a project
/// matches when every word is in its package name or its folder name. A word
/// found only in the path (`tekartik` in `github.com/tekartik/sqflite`) is a
/// match too, listed after the name matches. An empty [query] matches every
/// project.
///
/// The projects closest to [from] come first: the ones below [from], then
/// the ones below its parent, and so on up to the top folders of the cache.
/// At the same distance, an exact name first, then a name starting with the
/// word, a word of the name (`common` in `sqflite_common`), and the shortest
/// name. Without query, by path.
///
/// [limit] keeps the first ones only, [context] is the path context of the
/// cache (the io one by default).
List<DartProjectInfo> searchDartProjects(
  Iterable<DartProjectInfo> projects,
  String query, {
  String? from,
  int? limit,
  p.Context? context,
}) {
  context ??= p.context;
  var words = dartProjectSearchNormalize(
    query,
  ).split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
  var ancestors = from == null ? null : _selfAndAncestors(context, from);
  var separator = context.separator;
  var matches = <_Match>[];
  for (var project in projects) {
    var match = _match(project, words, context: context);
    if (match == null) {
      continue;
    }
    matches.add(
      _Match(
        project,
        pathOnly: match.pathOnly,
        score: match.score,
        distance: ancestors == null
            ? 0
            : _distance(ancestors, project.path, separator: separator),
      ),
    );
  }
  var byPath = words.isEmpty;
  matches.sort((match1, match2) {
    int compare(int value1, int value2) => value1.compareTo(value2);
    var result = compare(match1.pathOnly ? 1 : 0, match2.pathOnly ? 1 : 0);
    if (result == 0) {
      result = compare(match1.distance, match2.distance);
    }
    if (result == 0 && !byPath) {
      result = compare(match1.score, match2.score);
      if (result == 0) {
        result = compare(
          match1.project.name.length,
          match2.project.name.length,
        );
      }
    }
    if (result == 0) {
      result = match1.project.path.compareTo(match2.project.path);
    }
    return result;
  });
  var found = matches.map((match) => match.project);
  return (limit == null ? found : found.take(limit)).toList();
}

/// A project matching the query.
class _Match {
  final DartProjectInfo project;

  /// True when a word was only found in the path.
  final bool pathOnly;

  /// How good the name matches, the lower the better.
  final int score;

  /// How many folders up from the search folder hold the project.
  final int distance;

  _Match(
    this.project, {
    required this.pathOnly,
    required this.score,
    required this.distance,
  });
}

/// Score of a word found in the path only.
const _pathScore = 4;

/// How [project] matches [words], null when it does not.
({bool pathOnly, int score})? _match(
  DartProjectInfo project,
  List<String> words, {
  required p.Context context,
}) {
  if (words.isEmpty) {
    return (pathOnly: false, score: 0);
  }
  var name = dartProjectSearchNormalize(project.name);
  var folderName = dartProjectSearchNormalize(context.basename(project.path));
  String? path;
  var pathOnly = false;
  var score = 0;
  for (var word in words) {
    var nameScore = _textScore(name, word);
    var folderScore = _textScore(folderName, word);
    var wordScore = (nameScore == null || folderScore == null)
        ? nameScore ?? folderScore
        : (nameScore < folderScore ? nameScore : folderScore);
    if (wordScore == null) {
      path ??= dartProjectSearchNormalize(project.path);
      if (!path.contains(word)) {
        return null;
      }
      pathOnly = true;
      wordScore = _pathScore;
    }
    score += wordScore;
  }
  return (pathOnly: pathOnly, score: score);
}

/// How [word] is found in [text], the lower the better, null when not found.
///
/// 0 for the text itself, 1 at its start, 2 at the start of one of its words
/// (after `_`, `-`, `.` or a space), 3 anywhere.
int? _textScore(String text, String word) {
  if (text == word) {
    return 0;
  }
  var index = text.indexOf(word);
  if (index < 0) {
    return null;
  }
  if (index == 0) {
    return 1;
  }
  while (index > 0) {
    if (_wordSeparators.contains(text[index - 1])) {
      return 2;
    }
    index = text.indexOf(word, index + 1);
  }
  return 3;
}

const _wordSeparators = {'_', '-', '.', ' '};

/// [path] and its parents up to the root, [path] first.
List<String> _selfAndAncestors(p.Context context, String path) {
  var folder = context.canonicalize(context.absolute(path));
  var ancestors = [folder];
  while (true) {
    var parent = context.dirname(folder);
    if (parent == folder) {
      return ancestors;
    }
    ancestors.add(folder = parent);
  }
}

/// How many folders up from the first of [ancestors] hold [path], the number
/// of ancestors when none (another drive).
int _distance(
  List<String> ancestors,
  String path, {
  required String separator,
}) {
  for (var i = 0; i < ancestors.length; i++) {
    var ancestor = ancestors[i];
    if (path == ancestor ||
        path.startsWith(
          ancestor.endsWith(separator) ? ancestor : '$ancestor$separator',
        )) {
      return i;
    }
  }
  return ancestors.length;
}
