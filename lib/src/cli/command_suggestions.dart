import 'dart:collection';
import 'dart:math' as math;

import 'package:args/command_runner.dart';

String commandSuggestionsText<T>(
  String requested,
  Iterable<Command<T>> commands, {
  String? commandPrefix,
  int maxSuggestions = 3,
}) {
  final suggestions = commandSuggestions(
    requested,
    commands,
    maxSuggestions: maxSuggestions,
  );
  if (suggestions.isEmpty) {
    return '';
  }

  final prefix = commandPrefix == null || commandPrefix.isEmpty
      ? ''
      : '$commandPrefix ';
  return [
    '',
    '',
    'Did you mean one of these?',
    for (final suggestion in suggestions) '  $prefix$suggestion',
  ].join('\n');
}

List<String> commandSuggestions<T>(
  String requested,
  Iterable<Command<T>> commands, {
  int maxSuggestions = 3,
}) {
  final query = _normalize(requested);
  if (query.isEmpty) {
    return const [];
  }

  final scores = <Command<T>, _SuggestionScore>{};
  for (final command in LinkedHashSet<Command<T>>.of(commands)) {
    if (command.hidden) {
      continue;
    }
    for (final candidate in _candidateNames(command)) {
      final score = _score(query, _normalize(candidate));
      if (score == null) {
        continue;
      }
      final previous = scores[command];
      if (previous == null || score < previous) {
        scores[command] = score;
      }
    }
  }

  final ranked = scores.entries.toList()
    ..sort((left, right) {
      final scoreComparison = left.value.compareTo(right.value);
      if (scoreComparison != 0) {
        return scoreComparison;
      }
      return left.key.name.compareTo(right.key.name);
    });

  return [for (final entry in ranked.take(maxSuggestions)) entry.key.name];
}

Iterable<String> _candidateNames<T>(Command<T> command) sync* {
  yield command.name;
  yield* command.aliases;
  yield* command.suggestionAliases;
  yield* _semanticSuggestionAliases[command.name] ?? const [];
}

const _semanticSuggestionAliases = <String, List<String>>{
  'clean': ['clear'],
  'current': ['selected', 'active'],
  'get': ['install', 'fetch'],
  'list': ['ls'],
  'remove': ['rm', 'delete'],
  'upgrade': ['update'],
};

_SuggestionScore? _score(String query, String candidate) {
  if (candidate.isEmpty) {
    return null;
  }
  if (query == candidate) {
    return const _SuggestionScore(_MatchKind.exactAlias, 0);
  }
  if (candidate.startsWith(query) && query.length >= 2) {
    return _SuggestionScore(_MatchKind.prefix, candidate.length - query.length);
  }

  final distance = _damerauLevenshteinDistance(query, candidate);
  if (distance <= _distanceLimit(query.length, candidate.length)) {
    return _SuggestionScore(
      _MatchKind.editDistance,
      distance * 4 + (query.length - candidate.length).abs(),
    );
  }

  if (query.length >= 2 && _isOrderedSubsequence(query, candidate)) {
    return _SuggestionScore(
      _MatchKind.subsequence,
      candidate.length - query.length,
    );
  }

  return null;
}

int _distanceLimit(int queryLength, int candidateLength) {
  final longer = math.max(queryLength, candidateLength);
  if (longer <= 4) {
    return 1;
  }
  if (longer <= 8) {
    return 2;
  }
  return 3;
}

String _normalize(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[-_\s]+'), '');
}

bool _isOrderedSubsequence(String query, String candidate) {
  var queryIndex = 0;
  for (
    var candidateIndex = 0;
    candidateIndex < candidate.length && queryIndex < query.length;
    candidateIndex += 1
  ) {
    if (query.codeUnitAt(queryIndex) == candidate.codeUnitAt(candidateIndex)) {
      queryIndex += 1;
    }
  }
  return queryIndex == query.length;
}

int _damerauLevenshteinDistance(String left, String right) {
  final rows = left.length + 1;
  final columns = right.length + 1;
  final distances = List.generate(rows, (row) => List<int>.filled(columns, 0));

  for (var row = 0; row < rows; row += 1) {
    distances[row][0] = row;
  }
  for (var column = 0; column < columns; column += 1) {
    distances[0][column] = column;
  }

  for (var row = 1; row < rows; row += 1) {
    for (var column = 1; column < columns; column += 1) {
      final substitutionCost =
          left.codeUnitAt(row - 1) == right.codeUnitAt(column - 1) ? 0 : 1;
      distances[row][column] = math.min(
        math.min(
          distances[row - 1][column] + 1,
          distances[row][column - 1] + 1,
        ),
        distances[row - 1][column - 1] + substitutionCost,
      );

      if (row > 1 &&
          column > 1 &&
          left.codeUnitAt(row - 1) == right.codeUnitAt(column - 2) &&
          left.codeUnitAt(row - 2) == right.codeUnitAt(column - 1)) {
        distances[row][column] = math.min(
          distances[row][column],
          distances[row - 2][column - 2] + 1,
        );
      }
    }
  }

  return distances[left.length][right.length];
}

enum _MatchKind { exactAlias, prefix, editDistance, subsequence }

class _SuggestionScore implements Comparable<_SuggestionScore> {
  const _SuggestionScore(this.kind, this.penalty);

  final _MatchKind kind;
  final int penalty;

  @override
  int compareTo(_SuggestionScore other) {
    final kindComparison = kind.index.compareTo(other.kind.index);
    if (kindComparison != 0) {
      return kindComparison;
    }
    return penalty.compareTo(other.penalty);
  }

  bool operator <(_SuggestionScore other) => compareTo(other) < 0;
}
