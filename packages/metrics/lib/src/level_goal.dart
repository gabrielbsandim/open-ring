import 'package:metrics/src/level.dart';
import 'package:metrics/src/local_date.dart';

const weekGoalMin = 3;
const weekGoalMax = 7;
const weekGoalDefault = 4;
const bestWeekMinDays = 4;

enum WeekDayKind { met, missed, tagged, blank, noLine, today, future }

typedef WeekDay = ({LocalDate date, WeekDayKind kind});
typedef BestDay = ({LocalDate date, int score});
typedef BestLevel = ({LocalDate date, double level});
typedef BestWeek = ({LocalDate monday, int average});

int clampWeekGoal(int goal) => goal.clamp(weekGoalMin, weekGoalMax);

LocalDate mondayOf(LocalDate date) =>
    date.addDays(1 - DateTime.utc(date.year, date.month, date.day).weekday);

final class LevelWeek {
  new({required Iterable<WeekDay> days, required this.goal})
    : days = List.unmodifiable(days);

  final List<WeekDay> days;
  final int goal;

  Iterable<WeekDay> get _met =>
      days.where((day) => day.kind == WeekDayKind.met);

  int get count => _met.length;

  bool get met => count >= goal;

  /// The day that completed the goal.
  LocalDate? get metOn => met ? _met.elementAt(goal - 1).date : null;

  int get need => met ? 0 : goal - count;

  /// Days that can still count: today, once it closes, and the days ahead.
  int get open => days
      .where(
        (day) =>
            day.kind == WeekDayKind.today || day.kind == WeekDayKind.future,
      )
      .length;

  bool get reachable => need <= open;
}

/// Monday to Sunday around [containing], or around [today] without it.
/// [track] holds closed days only, so today never counts before it closes.
LevelWeek levelWeek(
  LevelTrack track, {
  required LocalDate today,
  required int goal,
  Set<LocalDate> tagged = const {},
  LocalDate? containing,
}) {
  final monday = mondayOf(containing ?? today);
  return LevelWeek(
    goal: clampWeekGoal(goal),
    days: [
      for (var i = 0; i < 7; i++)
        (
          date: monday.addDays(i),
          kind: _kind(track, monday.addDays(i), today, tagged),
        ),
    ],
  );
}

WeekDayKind _kind(
  LevelTrack track,
  LocalDate date,
  LocalDate today,
  Set<LocalDate> tagged,
) {
  if (date.compareTo(today) > 0) return WeekDayKind.future;
  if (tagged.contains(date)) return WeekDayKind.tagged;
  if (date == today) return WeekDayKind.today;
  final step = track.on(date);
  final score = step?.day.score;
  if (step == null || score == null) return WeekDayKind.blank;
  if (step.day.excluded) return WeekDayKind.tagged;
  final line = step.before;
  if (line == null) return WeekDayKind.noLine;
  return levelSide(score, line) == LevelSide.below
      ? WeekDayKind.missed
      : WeekDayKind.met;
}

final class LevelBests {
  const new({
    this.day,
    this.previousDay,
    this.level,
    this.previousLevel,
    this.week,
  });

  final BestDay? day;
  final BestDay? previousDay;
  final BestLevel? level;
  final BestLevel? previousLevel;
  final BestWeek? week;
}

/// Bests over the closed days of [track]. A tie keeps the earlier holder,
/// and the Level is compared at the one decimal the screens show.
LevelBests levelBests(LevelTrack track, {required LocalDate today}) {
  BestDay? day;
  BestDay? previousDay;
  BestLevel? level;
  BestLevel? previousLevel;
  for (final step in track.steps) {
    final score = step.day.score;
    if (!step.counted || score == null) continue;
    if (day == null || score > day.score) {
      previousDay = day;
      day = (date: step.date, score: score);
    }
    final after = step.after;
    if (after == null) continue;
    final shown = (after * 10).round() / 10;
    if (level == null || shown > level.level) {
      previousLevel = level;
      level = (date: step.date, level: shown);
    }
  }
  return LevelBests(
    day: day,
    previousDay: previousDay,
    level: level,
    previousLevel: previousLevel,
    week: _bestWeek(track, today),
  );
}

// Only whole weeks already over, each inside the days the track holds.
BestWeek? _bestWeek(LevelTrack track, LocalDate today) {
  if (track.steps.isEmpty) return null;
  final first = track.steps.first.date;
  final current = mondayOf(today);
  var monday = mondayOf(first);
  if (monday.compareTo(first) < 0) monday = monday.addDays(7);
  BestWeek? best;
  for (; monday.compareTo(current) < 0; monday = monday.addDays(7)) {
    final scores = [
      for (var i = 0; i < 7; i++)
        if (track.on(monday.addDays(i)) case LevelStep(
          counted: true,
          day: LevelDay(:final score?),
        ))
          score,
    ];
    if (scores.length < bestWeekMinDays) continue;
    final average = (scores.reduce((a, b) => a + b) / scores.length).round();
    if (best == null || average > best.average) {
      best = (monday: monday, average: average);
    }
  }
  return best;
}

final class LevelCelebration {
  const new({
    this.goal,
    this.day,
    this.previousDay,
    this.level,
    this.previousLevel,
  });

  /// The weekly goal, when yesterday was the day that completed it.
  final int? goal;
  final BestDay? day;
  final BestDay? previousDay;
  final BestLevel? level;
  final BestLevel? previousLevel;

  bool get hasBest => day != null || level != null;

  bool get isEmpty => goal == null && !hasBest;
}

/// What yesterday earned. A best needs an earlier one to beat, and the
/// highest Level is celebrated once a week, on the first day that sets it.
LevelCelebration levelCelebration(
  LevelTrack track, {
  required LocalDate today,
  required int goal,
  Set<LocalDate> tagged = const {},
}) {
  final yesterday = today.addDays(-1);
  final week = levelWeek(
    track,
    today: today,
    goal: goal,
    tagged: tagged,
    containing: yesterday,
  );
  final bests = levelBests(track, today: today);
  final day = bests.day;
  final previousDay = bests.previousDay;
  final level = bests.level;
  final previousLevel = bests.previousLevel;
  final newDay = day != null && previousDay != null && day.date == yesterday;
  final newLevel =
      level != null &&
      previousLevel != null &&
      level.date == yesterday &&
      previousLevel.date.compareTo(mondayOf(yesterday)) < 0;
  return LevelCelebration(
    goal: week.metOn == yesterday ? week.goal : null,
    day: newDay ? day : null,
    previousDay: newDay ? previousDay : null,
    level: newLevel ? level : null,
    previousLevel: newLevel ? previousLevel : null,
  );
}
