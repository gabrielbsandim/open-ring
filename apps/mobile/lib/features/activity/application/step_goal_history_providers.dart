import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/domain/step_goal_history.dart';

final stepGoalHistoryProvider = Provider<StepGoalHistory>(
  (ref) => InMemoryStepGoalHistory(),
);

final stepGoalChangesProvider = FutureProvider<List<StepGoalChange>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(stepGoalHistoryProvider).changes();
});
