import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_view.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';

const activityWeekDays = 7;

final activityHistoryReaderProvider = Provider<ActivityHistoryReader>(
  (ref) => const EmptyActivityHistoryReader(),
);

final stepGoalProvider = Provider<int>(
  (ref) =>
      ref.watch(userProfileProvider).value?.dailyStepGoal ?? defaultStepGoal,
);

final activityDaysProvider = FutureProvider<Map<LocalDate, DailyActivity>>((
  ref,
) async {
  ref.watch(dataRevisionProvider);
  final reader = ref.watch(activityHistoryReaderProvider);
  final today = ref.watch(currentDateProvider);
  final days = await reader.dailyActivity(
    from: today.addDays(-chronicLoadDays),
    to: today,
  );
  return {for (final d in days) d.date: d};
});

final activityDayProvider = FutureProvider<ActivityDayView>((ref) async {
  ref.watch(dataRevisionProvider);
  final reader = ref.watch(activityHistoryReaderProvider);
  final today = ref.watch(currentDateProvider);
  final goal = ref.watch(stepGoalProvider);
  final (days, slots) = await (
    ref.watch(activityDaysProvider.future),
    reader.activitySlots(from: today, to: today),
  ).wait;
  return ActivityDayView(
    date: today,
    stepGoal: goal,
    today: days[today],
    hourlySteps: hourlySteps(today, slots),
    week: [
      for (var age = activityWeekDays - 1; age >= 0; age--)
        (date: today.addDays(-age), activity: days[today.addDays(-age)]),
    ],
  );
});
