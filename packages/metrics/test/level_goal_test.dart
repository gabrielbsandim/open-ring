import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

// A Monday, so week rows read straight off the lists below.
const _start = LocalDate(2026, 9, 7);

LevelTrack _track(List<int?> scores, {Set<int> excluded = const {}}) =>
    levelTrack([
      for (final (index, score) in scores.indexed)
        LevelDay(
          date: _start.addDays(index),
          score: score,
          excluded: excluded.contains(index),
        ),
    ]);

List<WeekDayKind> _kinds(LevelWeek week) => [
  for (final day in week.days) day.kind,
];

void main() {
  test('the week runs from Monday to Sunday', () {
    expect(
      mondayOf(const LocalDate(2026, 11, 10)),
      const LocalDate(2026, 11, 9),
    );
    expect(
      mondayOf(const LocalDate(2026, 11, 9)),
      const LocalDate(2026, 11, 9),
    );
    expect(
      mondayOf(const LocalDate(2026, 11, 15)),
      const LocalDate(2026, 11, 9),
    );
  });

  test('the goal stays between 3 and 7', () {
    expect(clampWeekGoal(1), 3);
    expect(clampWeekGoal(5), 5);
    expect(clampWeekGoal(9), 7);
  });

  test('a day on the line or above counts, a day below does not', () {
    final track = _track([...List.filled(14, 70), 70, 71, 60, null, 90]);
    final today = _start.addDays(19);
    final week = levelWeek(track, today: today, goal: 4);

    expect(_kinds(week), [
      WeekDayKind.met,
      WeekDayKind.met,
      WeekDayKind.missed,
      WeekDayKind.blank,
      WeekDayKind.met,
      WeekDayKind.today,
      WeekDayKind.future,
    ]);
    expect(week.count, 3);
    expect(week.met, isFalse);
    expect(week.need, 1);
    expect(week.open, 2);
    expect(week.reachable, isTrue);
    expect(week.metOn, isNull);
  });

  test('a tagged day counts neither for nor against', () {
    final track = _track([...List.filled(14, 70), 90, 90, 90], excluded: {15});
    final today = _start.addDays(17);
    final week = levelWeek(
      track,
      today: today,
      goal: 3,
      tagged: {_start.addDays(15), today},
    );

    expect(_kinds(week).sublist(0, 4), [
      WeekDayKind.met,
      WeekDayKind.tagged,
      WeekDayKind.met,
      WeekDayKind.tagged,
    ]);
    expect(week.count, 2);
    expect(week.open, 3);
  });

  test('the goal is met on the day that completes it', () {
    final track = _track([...List.filled(14, 70), 80, 60, 80, 80, 80]);
    final week = levelWeek(track, today: _start.addDays(19), goal: 3);

    expect(week.met, isTrue);
    expect(week.need, 0);
    expect(week.metOn, _start.addDays(17));
  });

  test('a week that cannot reach the goal says so', () {
    final track = _track([...List.filled(14, 70), 60, 60, 60, 60, 60]);
    final week = levelWeek(track, today: _start.addDays(19), goal: 4);

    expect(week.need, 4);
    expect(week.open, 2);
    expect(week.reachable, isFalse);
  });

  test('days before the Level exists have no line to pass', () {
    final track = _track(List.filled(9, 70));
    final week = levelWeek(track, today: _start.addDays(9), goal: 4);

    expect(_kinds(week).sublist(0, 3), [
      WeekDayKind.noLine,
      WeekDayKind.noLine,
      WeekDayKind.today,
    ]);
    expect(week.count, 0);
  });

  test('the best day keeps the earlier holder on a tie', () {
    final track = _track([70, 85, 60, 85, 99], excluded: {4});
    final bests = levelBests(track, today: _start.addDays(5));

    expect(bests.day, (date: _start.addDays(1), score: 85));
    expect(bests.previousDay, (date: _start, score: 70));
    expect(bests.level, isNull);
    expect(bests.week, isNull);
  });

  test('the highest Level is compared at one decimal', () {
    final track = _track([...List.filled(14, 70), 80, 70, 60]);
    final bests = levelBests(track, today: _start.addDays(17));

    expect(bests.level?.date, _start.addDays(14));
    expect(bests.level?.level, 70.4);
    expect(bests.previousLevel, (date: _start.addDays(13), level: 70.0));
  });

  test('the best week needs four counted days and must be over', () {
    final track = _track([
      90,
      90,
      90,
      null,
      null,
      null,
      null,
      80,
      80,
      80,
      81,
      null,
      null,
      null,
      70,
      70,
      70,
      70,
      70,
      70,
      70,
      99,
      99,
      99,
      99,
    ]);
    final bests = levelBests(track, today: _start.addDays(25));

    expect(bests.week, (monday: _start.addDays(7), average: 80));
  });

  test('a week that starts before the first day kept is left out', () {
    final days = [
      for (var i = 2; i < 16; i++)
        LevelDay(date: _start.addDays(i), score: i < 7 ? 95 : 60),
    ];
    final bests = levelBests(levelTrack(days), today: _start.addDays(16));

    expect(bests.week, (monday: _start.addDays(7), average: 60));
  });
}
