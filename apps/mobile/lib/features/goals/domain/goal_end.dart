import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/domain/step_goal_history.dart';
import 'package:open_ring/features/goals/domain/goal.dart';

typedef StepGoalRaise = ({int from, int to});

/// The step goal the plan raised: from the goal in force the day before the
/// goal started to the one in force now. Null unless an accepted steps week
/// of this goal went above the starting goal, so a raise by hand alone is
/// never offered back as the plan's.
StepGoalRaise? planRaise({
  required Goal goal,
  required List<GoalWeek> weeks,
  required List<StepGoalChange> changes,
  required int current,
}) {
  final from = stepGoalOn(
    goal.startedOn.addDays(-1),
    changes: changes,
    current: current,
  );
  if (current <= from) return null;
  final raised = weeks.any((week) => _raisedSteps(week, above: from));
  if (!raised) return null;
  return (from: from, to: current);
}

bool _raisedSteps(GoalWeek week, {required int above}) {
  final change = week.change;
  final to = change?.to;
  if (week.answer != WeekAnswer.accepted || to == null) return false;
  return change?.kind == LeverKind.steps && to > above;
}
