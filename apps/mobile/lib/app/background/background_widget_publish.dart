import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/application/step_goal_history_providers.dart';
import 'package:open_ring/features/activity/infrastructure/drift_activity_history_reader.dart';
import 'package:open_ring/features/activity/infrastructure/drift_step_goal_history.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/body/infrastructure/drift_weigh_in_store.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/infrastructure/drift_goal_store.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/heart/infrastructure/drift_heart_history_reader.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/infrastructure/drift_day_tag_store.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/infrastructure/drift_user_profile_store.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_imported_sleep_reader.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_rem_reporting_reader.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_sleep_history_reader.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/infrastructure/drift_ring_status_reader.dart';
import 'package:open_ring/features/widgets/application/widget_providers.dart';
import 'package:open_ring/features/widgets/application/widget_publisher.dart';
import 'package:open_ring/features/widgets/domain/widget_gateway.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/infrastructure/drift_imported_workout_reader.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_history_reader.dart';

Future<void> publishWidgetSnapshot(
  AppDatabase database,
  WidgetGateway gateway, {
  DateTime Function() clock = DateTime.now,
  ModuleStore? modules,
  HideNumbersStore? hideNumbers,
}) async {
  final container = ProviderContainer(
    overrides: [
      clockProvider.overrideWithValue(clock),
      moduleStoreProvider.overrideWithValue(modules ?? InMemoryModuleStore()),
      hideNumbersStoreProvider.overrideWithValue(
        hideNumbers ?? InMemoryHideNumbersStore(),
      ),
      weighInStoreProvider.overrideWithValue(DriftWeighInStore(database)),
      dayTagStoreProvider.overrideWithValue(DriftDayTagStore(database)),
      stepGoalHistoryProvider.overrideWithValue(DriftStepGoalHistory(database)),
      goalStoreProvider.overrideWithValue(DriftGoalStore(database)),
      sleepHistoryReaderProvider.overrideWithValue(
        DriftSleepHistoryReader(database),
      ),
      importedSleepReaderProvider.overrideWithValue(
        DriftImportedSleepReader(database),
      ),
      remReportingReaderProvider.overrideWithValue(
        DriftRemReportingReader(database),
      ),
      heartHistoryReaderProvider.overrideWithValue(
        DriftHeartHistoryReader(database),
      ),
      activityHistoryReaderProvider.overrideWithValue(
        DriftActivityHistoryReader(database),
      ),
      ringStatusReaderProvider.overrideWithValue(
        DriftRingStatusReader(database),
      ),
      userProfileStoreProvider.overrideWithValue(
        DriftUserProfileStore(database),
      ),
      workoutHistoryReaderProvider.overrideWithValue(
        DriftWorkoutHistoryReader(database),
      ),
      importedWorkoutReaderProvider.overrideWithValue(
        DriftImportedWorkoutReader(database),
      ),
    ],
  );
  try {
    await (
      container.read(userProfileProvider.future),
      container.read(enabledModulesProvider.future),
      container.read(hideNumbersProvider.future),
    ).wait;
    final snapshot = await container.read(widgetSnapshotProvider.future);
    await WidgetPublisher(gateway).snapshot(snapshot);
  } finally {
    container.dispose();
  }
}
