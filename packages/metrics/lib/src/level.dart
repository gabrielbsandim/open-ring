import 'dart:math' as math;

import 'package:metrics/src/local_date.dart';

const levelSeedDays = 14;
const levelTimeConstantDays = 28;

// The share of the gap to the day's score that one counted day closes.
final double levelAlpha = 1 - math.exp(-1 / levelTimeConstantDays);

enum LevelSide { below, on, above }

final class LevelDay {
  const new({required this.date, required this.score, this.excluded = false});

  final LocalDate date;
  final int? score;

  /// A day the user set aside (sick, travel, rest): visible, never counted.
  final bool excluded;

  bool get counted => score != null && !excluded;
}

final class LevelStep {
  const new({required this.day, required this.before, required this.after});

  final LevelDay day;
  final double? before;
  final double? after;

  LocalDate get date => day.date;
  bool get counted => day.counted;

  double? get effect {
    final from = before;
    final to = after;
    if (!counted || from == null || to == null) return null;
    return to - from;
  }
}

final class LevelTrack {
  new(Iterable<LevelStep> steps) : steps = List.unmodifiable(steps);

  final List<LevelStep> steps;

  double? get level => steps.isEmpty ? null : steps.last.after;

  int get counted => steps.where((step) => step.counted).length;

  int get missing => math.max(0, levelSeedDays - counted);

  LevelStep? on(LocalDate date) {
    for (final step in steps) {
      if (step.date == date) return step;
    }
    return null;
  }

  /// The line a day is compared with: the Level as it stood before that day.
  double? lineOn(LocalDate date) => on(date)?.before;

  /// How much of today's Level each counted day still carries, newest first.
  Map<LocalDate, double> get weights {
    final result = <LocalDate, double>{};
    var weight = levelAlpha;
    for (final step in steps.reversed) {
      if (!step.counted || step.before == null) continue;
      result[step.date] = weight;
      weight *= 1 - levelAlpha;
    }
    return result;
  }
}

/// Walks closed days, oldest first. The Level starts as the mean of the
/// first [levelSeedDays] counted days and then moves by [levelAlpha].
LevelTrack levelTrack(Iterable<LevelDay> days) {
  final seed = <int>[];
  final steps = <LevelStep>[];
  double? level;
  for (final day in days) {
    final before = level;
    level = _advance(level, seed, day);
    steps.add(LevelStep(day: day, before: before, after: level));
  }
  return LevelTrack(steps);
}

double? _advance(double? level, List<int> seed, LevelDay day) {
  final score = day.score;
  if (score == null || day.excluded) return level;
  if (level != null) return levelAfter(level, score);
  seed.add(score);
  if (seed.length < levelSeedDays) return null;
  return seed.reduce((a, b) => a + b) / seed.length;
}

double levelAfter(double level, int score) =>
    level + levelAlpha * (score - level);

/// A whole score against a one decimal Level: compared with the Level
/// rounded to a whole number, so 71 against 71.4 is on the line.
LevelSide levelSide(int score, double level) {
  final line = level.round();
  if (score > line) return LevelSide.above;
  if (score < line) return LevelSide.below;
  return LevelSide.on;
}
