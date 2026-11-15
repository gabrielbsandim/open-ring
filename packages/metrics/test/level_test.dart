import 'dart:math' as math;

import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const _start = LocalDate(2026, 10, 1);

List<LevelDay> _days(List<int?> scores, {Set<int> excluded = const {}}) => [
  for (final (index, score) in scores.indexed)
    LevelDay(
      date: _start.addDays(index),
      score: score,
      excluded: excluded.contains(index),
    ),
];

void main() {
  test('alpha closes about 3.5 percent of the gap', () {
    expect(levelAlpha, closeTo(0.0351, 0.0001));
    expect(levelAfter(70, 80) - 70, closeTo(0.35, 0.005));
    expect(levelAfter(70, 60) - 70, closeTo(-0.35, 0.005));
  });

  test('there is no Level before 14 counted days', () {
    final track = levelTrack(_days(List.filled(13, 70)));

    expect(track.level, isNull);
    expect(track.counted, 13);
    expect(track.missing, 1);
    expect(track.steps.every((step) => step.effect == null), isTrue);
  });

  test('the Level starts as the mean of the first 14 counted days', () {
    final track = levelTrack(
      _days([
        for (var i = 0; i < 14; i++)
          if (i.isEven) 60 else 80,
      ]),
    );

    expect(track.level, 70);
    expect(track.missing, 0);
    expect(track.steps.last.before, isNull);
    expect(track.lineOn(_start.addDays(13)), isNull);
  });

  test('after the seed each counted day moves the Level by alpha', () {
    final track = levelTrack(_days([...List.filled(14, 70), 80, 50]));
    final first = track.steps[14];
    final second = track.steps[15];

    expect(first.before, 70);
    expect(first.effect, closeTo(levelAlpha * 10, 1e-9));
    expect(second.before, first.after);
    expect(second.effect, closeTo(levelAlpha * (50 - first.after!), 1e-9));
    expect(track.level, second.after);
    expect(track.lineOn(_start.addDays(15)), first.after);
  });

  test('a day without a score or set aside leaves the Level where it was', () {
    final track = levelTrack(
      _days([...List.filled(14, 70), null, 20, 90], excluded: {15}),
    );

    expect(track.steps[14].after, 70);
    expect(track.steps[14].effect, isNull);
    expect(track.steps[15].after, 70);
    expect(track.steps[15].effect, isNull);
    expect(track.steps[15].counted, isFalse);
    expect(track.level, closeTo(70 + levelAlpha * 20, 1e-9));
    expect(track.counted, 15);
  });

  test('days set aside do not feed the seed', () {
    final track = levelTrack(
      _days([10, ...List.filled(14, 70)], excluded: {0}),
    );

    expect(track.level, 70);
    expect(track.on(_start)?.counted, isFalse);
  });

  test('weights fall with age and skip days that did not count', () {
    final track = levelTrack(
      _days([...List.filled(14, 70), 80, null, 60, 75], excluded: {16}),
    );
    final weights = track.weights;

    expect(weights[_start.addDays(17)], closeTo(levelAlpha, 1e-12));
    expect(
      weights[_start.addDays(14)],
      closeTo(levelAlpha * (1 - levelAlpha), 1e-12),
    );
    expect(weights.containsKey(_start.addDays(15)), isFalse);
    expect(weights.containsKey(_start.addDays(16)), isFalse);
    expect(weights.containsKey(_start.addDays(13)), isFalse);
  });

  test('a long run of one score converges on it and never passes it', () {
    final track = levelTrack(
      _days([...List.filled(14, 60), ...List.filled(200, 80)]),
    );

    expect(track.level, lessThan(80));
    expect(track.level, closeTo(80, 0.05));
    expect(track.level, closeTo(80 - 20 * math.pow(1 - levelAlpha, 200), 1e-9));
  });

  test('the side compares the score with the rounded Level', () {
    expect(levelSide(71, 71.4), LevelSide.on);
    expect(levelSide(72, 71.4), LevelSide.above);
    expect(levelSide(70, 71.4), LevelSide.below);
    expect(levelSide(72, 71.5), LevelSide.on);
    expect(levelSide(71, 71.5), LevelSide.below);
  });

  test('an empty history has no Level and misses the whole seed', () {
    final track = levelTrack(const []);

    expect(track.level, isNull);
    expect(track.missing, levelSeedDays);
    expect(track.on(_start), isNull);
  });
}
