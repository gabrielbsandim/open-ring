import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/open_score/application/celebration_providers.dart';
import 'package:open_ring/features/open_score/application/week_goal_providers.dart';
import 'package:open_ring/features/open_score/domain/celebration_store.dart';
import 'package:open_ring/features/open_score/domain/week_goal_store.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/settings/application/delete_all_data_controller.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/widgets/application/widget_providers.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/workout/application/workout_alert_providers.dart';
import 'package:open_ring/features/workout/domain/workout_alert_preferences.dart';

import '../../../helpers/fake_sync_scheduler.dart';
import '../../../helpers/in_memory_sync_interval_store.dart';
import '../../../helpers/in_memory_theme_mode_store.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart' show FakeSyncStore;
import '../../../helpers/settings_fakes.dart';

void main() {
  late InMemoryWorkoutAlertPreferences preferences;

  ProviderContainer container([FakeLocalDataEraser? eraser]) {
    preferences = InMemoryWorkoutAlertPreferences();
    final container = ProviderContainer(
      overrides: [
        localDataEraserProvider.overrideWithValue(
          eraser ?? FakeLocalDataEraser(),
        ),
        themeModeStoreProvider.overrideWithValue(
          InMemoryThemeModeStore(ThemeMode.dark),
        ),
        syncIntervalStoreProvider.overrideWithValue(
          InMemorySyncIntervalStore(SyncInterval.minutes15),
        ),
        syncSchedulerProvider.overrideWithValue(FakeSyncScheduler()),
        syncStoreProvider.overrideWithValue(FakeSyncStore()),
        unitSystemStoreProvider.overrideWithValue(
          InMemoryUnitSystemStore(UnitSystem.imperial),
        ),
        userProfileStoreProvider.overrideWithValue(
          InMemoryUserProfileStore(fullProfile),
        ),
        onboardingStoreProvider.overrideWithValue(
          InMemoryOnboardingStore(completed: true),
        ),
        todayWidgetConfigStoreProvider.overrideWithValue(
          InMemoryTodayWidgetConfigStore(TodayWidgetConfig()),
        ),
        moduleStoreProvider.overrideWithValue(
          InMemoryModuleStore({ModuleId.body}),
        ),
        weekGoalStoreProvider.overrideWithValue(InMemoryWeekGoalStore(6)),
        celebrationStoreProvider.overrideWithValue(InMemoryCelebrationStore()),
        workoutAlertPreferencesProvider.overrideWithValue(preferences),
      ],
    );
    addTearDown(container.dispose);
    container.listen(deleteAllDataProvider, (_, _) {});
    return container;
  }

  group('8: Delete all data and the ring lost alert', () {
    test('turns the switch back on', () async {
      final c = container();
      await c.read(workoutRingLostAlertProvider.future);
      await c.read(workoutRingLostAlertProvider.notifier).set(alert: false);
      expect(c.read(workoutRingLostAlertProvider).value, isFalse);
      // Stands in for the eraser: the stored key is gone, so the store reads
      // its default, and only an invalidated provider sees that.
      await preferences.setAlertRingLost(alert: true);

      expect(await c.read(deleteAllDataProvider.notifier).delete(), isTrue);

      expect(await c.read(workoutRingLostAlertProvider.future), isTrue);
    });

    test('a failed erase keeps the switch off', () async {
      final c = container(FakeLocalDataEraser(fail: true));
      await c.read(workoutRingLostAlertProvider.future);
      await c.read(workoutRingLostAlertProvider.notifier).set(alert: false);

      expect(await c.read(deleteAllDataProvider.notifier).delete(), isFalse);

      expect(c.read(workoutRingLostAlertProvider).value, isFalse);
      expect(await preferences.alertRingLost(), isFalse);
    });
  });
}
