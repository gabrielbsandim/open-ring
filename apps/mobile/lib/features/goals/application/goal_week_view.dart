import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/goal.dart';

/// The week in progress of the active goal, as a screen reads it.
sealed class GoalWeekView {
  const new();
}

final class GoalWeekOff extends GoalWeekView {
  const new();
}

final class GoalWeekNoGoal extends GoalWeekView {
  const new();
}

final class GoalWeekPaused extends GoalWeekView {
  const new({
    required this.goal,
    required this.until,
    required this.rule,
    required this.over,
  });

  final Goal goal;

  /// The last day of the pause, inclusive. The goal stays paused past it
  /// until something resumes it.
  final LocalDate? until;

  /// The rule of the review that paused the goal, null for a pause the
  /// person set.
  final ReviewRule? rule;

  /// Whether the last day has passed and the next block has not started.
  final bool over;
}

/// Losing fat with Body off: nothing is asked and nothing is counted.
final class GoalWeekHold extends GoalWeekView {
  const new({required this.goal});

  final Goal goal;
}

/// The base phase: the goal has no lever yet and waits for its first block.
final class GoalWeekBase extends GoalWeekView {
  const new({required this.goal, required this.rate});

  final Goal goal;

  /// The weight rate as of today for losing fat, null for any other goal and
  /// with no weigh-in.
  final WeightRate? rate;
}

/// The review of this Monday asked for a recovery week.
final class GoalWeekRecovery extends GoalWeekView {
  const new({required this.goal, required this.monday, required this.week});

  final Goal goal;
  final LocalDate monday;

  /// The week of the block under way, from 1.
  final int week;
}

final class GoalWeekRunning extends GoalWeekView {
  const new({
    required this.goal,
    required this.monday,
    required this.week,
    required this.levers,
    required this.review,
  });

  final Goal goal;
  final LocalDate monday;

  /// The week of the block under way, from 1.
  final int week;
  final List<LeverProgress> levers;

  /// The review of this Monday while its proposal waits for an answer.
  final GoalWeek? review;
}
