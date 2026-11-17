import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/application/step_goal_history_providers.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_end.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

/// What ending a goal did. [stepGoalFailed] keeps the goal ended: only the
/// profile step goal is left to write, through [GoalEnder.retryStepGoalBack].
enum GoalEndOutcome { ended, stepGoalFailed, refused }

final goalEnderProvider = NotifierProvider<GoalEnder, void>(GoalEnder.new);

/// The raise the end screen asks about, read while the goal is still active.
final goalEndRaiseProvider = FutureProvider<StepGoalRaise?>((ref) async {
  final goal = await ref.watch(activeGoalProvider.future);
  if (goal == null) return null;
  final weeks = await ref.watch(goalStoreProvider).weeks(goal.id);
  final changes = await ref.watch(stepGoalChangesProvider.future);
  return planRaise(
    goal: goal,
    weeks: weeks,
    changes: changes,
    current: ref.watch(stepGoalProvider),
  );
});

class GoalEnder extends Notifier<void> {
  @override
  void build() {}

  /// Ends the active goal as the person asked, then, with [stepGoalBack],
  /// puts that step goal back from today. The end is written first, since
  /// its refusal is what keeps a second tap from writing the goal twice.
  Future<GoalEndOutcome> end(GoalEndReason reason, {int? stepGoalBack}) async {
    if (reason != GoalEndReason.person && reason != GoalEndReason.switched) {
      throw ArgumentError.value(reason, 'reason', 'not chosen by the person');
    }
    if (!ref.read(goalsEnabledProvider) || ref.read(demoModeProvider)) {
      return GoalEndOutcome.refused;
    }
    final store = ref.read(goalStoreProvider);
    final goal = await store.active();
    if (goal == null) return GoalEndOutcome.refused;
    final ended = await store.end(
      goal.id,
      on: ref.read(currentDateProvider),
      reason: reason,
    );
    if (!ended) return GoalEndOutcome.refused;
    _bump();
    if (stepGoalBack == null) return GoalEndOutcome.ended;
    if (await retryStepGoalBack(stepGoalBack)) return GoalEndOutcome.ended;
    return GoalEndOutcome.stepGoalFailed;
  }

  /// Lowers the profile step goal to [steps] from today. It runs after the
  /// goal ended, so it needs no active goal, and it never raises the goal.
  /// False, with the failure logged, when the profile could not be saved.
  Future<bool> retryStepGoalBack(int steps) async {
    try {
      final held = await ref.read(userProfileProvider.future);
      final profile = held ?? const UserProfile();
      if (steps >= (profile.dailyStepGoal ?? defaultStepGoal)) return true;
      await ref
          .read(userProfileProvider.notifier)
          .save(
            UserProfile(
              birthYear: profile.birthYear,
              sex: profile.sex,
              heightCentimeters: profile.heightCentimeters,
              weightKilograms: profile.weightKilograms,
              maxHeartRate: profile.maxHeartRate,
              dailyStepGoal: steps,
            ),
          );
      return true;
    } on Object catch (error) {
      debugPrint('Goal step goal was not put back: $error');
      return false;
    }
  }

  void _bump() {
    if (!ref.mounted) return;
    ref.read(dataRevisionProvider.notifier).bump();
  }
}
