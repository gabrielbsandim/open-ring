import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

// A Monday.
const _start = LocalDate(2026, 9, 7);

LevelTrack _track(List<int?> scores) => levelTrack([
  for (final (index, score) in scores.indexed)
    LevelDay(date: _start.addDays(index), score: score),
]);

LevelCelebration _after(List<int?> scores, {int goal = 4}) => levelCelebration(
  _track(scores),
  today: _start.addDays(scores.length),
  goal: goal,
);

void main() {
  test('nothing to celebrate on an ordinary day', () {
    final result = _after([...List.filled(14, 70), 60, 60]);

    expect(result.isEmpty, isTrue);
    expect(result.hasBest, isFalse);
  });

  test('the goal is celebrated the morning after the day that met it', () {
    final met = _after([...List.filled(14, 70), 70, 70, 70], goal: 3);
    final later = _after([...List.filled(14, 70), 70, 70, 70, 70], goal: 3);

    expect(met.goal, 3);
    expect(later.goal, isNull);
  });

  test('a goal met on Sunday is celebrated on Monday', () {
    final result = _after([
      ...List.filled(14, 70),
      60,
      60,
      60,
      60,
      70,
      70,
      70,
    ], goal: 3);

    expect(result.goal, 3);
  });

  test('a best day needs an earlier best to beat', () {
    final first = _after([80]);
    final beaten = _after([80, 70, 90]);
    final tied = _after([80, 70, 80]);

    expect(first.day, isNull);
    expect(beaten.day, (date: _start.addDays(2), score: 90));
    expect(beaten.previousDay, (date: _start, score: 80));
    expect(tied.day, isNull);
  });

  test('the highest Level is celebrated once a week', () {
    final first = _after([...List.filled(14, 70), 90]);
    final second = _after([...List.filled(14, 70), 90, 90]);
    final nextWeek = _after([
      ...List.filled(14, 70),
      90,
      70,
      70,
      70,
      70,
      70,
      70,
      99,
    ]);

    expect(first.level?.date, _start.addDays(14));
    expect(first.previousLevel, (date: _start.addDays(13), level: 70.0));
    expect(second.level, isNull);
    expect(second.day, isNull);
    expect(nextWeek.level?.date, _start.addDays(21));
    expect(nextWeek.previousLevel?.date, _start.addDays(14));
  });
}
