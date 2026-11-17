import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/domain/goal_path.dart';
import 'package:open_ring/features/goals/domain/review_inputs.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';

/// The path with the weigh-ins and the trend it was read from.
typedef GoalPathView = ({
  GoalPath path,
  List<DailyValue> daily,
  List<DailyValue> line,
});

/// The path of the weight goal under way, null for any other goal.
final goalPathProvider = FutureProvider<GoalPathView?>((ref) async {
  final goal = await ref.watch(activeGoalProvider.future);
  if (goal == null || goal.kind != GoalKind.loseFat) return null;
  final summary = await ref.watch(weightSummaryProvider.future);
  final profile = await ref.watch(userProfileProvider.future);
  final on = goalPathDay(goal, ref.watch(currentDateProvider));
  final daily = summary?.daily ?? const <DailyValue>[];
  final past = [
    for (final day in daily)
      if (day.date.compareTo(on) <= 0) day,
  ];
  return (
    path: goalPath(
      goal: goal,
      snapshot: weightSnapshot(daily: daily, asOf: on),
      heightCm: profile?.heightCentimeters,
      on: on,
    ),
    daily: past,
    line: weightTrend(past),
  );
});
