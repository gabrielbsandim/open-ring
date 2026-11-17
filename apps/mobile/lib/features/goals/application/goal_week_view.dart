import 'package:meta/meta.dart';
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

/// Losing fat with Body off: the view shows no lever and no count. A goal
/// with levers is still reviewed each week and can still be paused or ended.
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

/// The maintenance weeks after a block, as the running layout shows them.
@immutable
final class GoalMaintenance {
  const new({required this.until, required this.over});

  /// The last day of maintenance, inclusive.
  final LocalDate until;

  /// Whether the last day has passed and the next block has not started.
  final bool over;

  @override
  bool operator ==(Object other) =>
      other is GoalMaintenance && other.until == until && other.over == over;

  @override
  int get hashCode => Object.hash(until, over);
}

/// The review of this Monday asked for a recovery week.
final class GoalWeekRecovery extends GoalWeekView {
  const new({
    required this.goal,
    required this.monday,
    required this.week,
    this.maintenance,
  });

  final Goal goal;
  final LocalDate monday;

  /// The week of the block under way, from 1.
  final int week;

  /// Set while the goal keeps after a block.
  final GoalMaintenance? maintenance;
}

final class GoalWeekRunning extends GoalWeekView {
  const new({
    required this.goal,
    required this.monday,
    required this.week,
    required this.levers,
    required this.review,
    this.maintenance,
  });

  final Goal goal;
  final LocalDate monday;

  /// The week of the block under way, from 1.
  final int week;
  final List<LeverProgress> levers;

  /// The review of this Monday while its proposal waits for an answer.
  final GoalWeek? review;

  /// Set while the goal keeps after a block.
  final GoalMaintenance? maintenance;
}

/// Whether the end screen offers to move to maintenance now: only a running
/// block of losing fat, which is the only goal with blocks.
bool canMaintainNow(GoalWeekView view) {
  final goal = switch (view) {
    GoalWeekRunning(:final goal, maintenance: null) => goal,
    GoalWeekRecovery(:final goal, maintenance: null) => goal,
    _ => null,
  };
  if (goal == null) return false;
  return goal.kind == GoalKind.loseFat && goal.phase == GoalPhase.block;
}
