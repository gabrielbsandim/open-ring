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
  const new({required this.goal, required this.until});

  final Goal goal;

  /// The last day of the pause, inclusive. The goal stays paused past it
  /// until something resumes it.
  final LocalDate? until;
}

final class GoalWeekRunning extends GoalWeekView {
  const new({
    required this.goal,
    required this.monday,
    required this.week,
    required this.levers,
  });

  final Goal goal;
  final LocalDate monday;

  /// The week of the block under way, from 1.
  final int week;
  final List<LeverProgress> levers;
}
