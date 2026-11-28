import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/background/background_sync_dispatcher.dart';
import 'package:open_ring/app/theme/shared_preferences_theme_mode_store.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/database/app_database_provider.dart';
import 'package:open_ring/core/database/open_app_database.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/application/step_goal_history_providers.dart';
import 'package:open_ring/features/activity/infrastructure/drift_activity_history_reader.dart';
import 'package:open_ring/features/activity/infrastructure/drift_step_goal_history.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_report_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/infrastructure/drift_ai_report_store.dart';
import 'package:open_ring/features/ai/infrastructure/secure_storage_secret_store.dart';
import 'package:open_ring/features/ai/infrastructure/shared_preferences_ai_config_store.dart';
import 'package:open_ring/features/ai/infrastructure/shared_preferences_ai_run_marker_store.dart';
import 'package:open_ring/features/backup/application/backup_archive.dart';
import 'package:open_ring/features/backup/application/backup_providers.dart';
import 'package:open_ring/features/backup/application/pending_restore.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/infrastructure/drift_weigh_in_store.dart';
import 'package:open_ring/features/body/infrastructure/shared_preferences_hide_numbers_store.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/infrastructure/demo_workout_store.dart';
import 'package:open_ring/features/demo/infrastructure/drift_demo_data_store.dart';
import 'package:open_ring/features/demo/infrastructure/shared_preferences_demo_mode_store.dart';
import 'package:open_ring/features/food/application/food_energy_gate.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_analysis_trigger.dart';
import 'package:open_ring/features/food/application/meal_recovery.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_store.dart';
import 'package:open_ring/features/food/infrastructure/image_picker_meal_camera.dart';
import 'package:open_ring/features/food/infrastructure/image_picker_meal_gallery.dart';
import 'package:open_ring/features/food/infrastructure/io_photo_store.dart';
import 'package:open_ring/features/food/infrastructure/shared_preferences_food_energy_store.dart';
import 'package:open_ring/features/goals/application/goal_review_trigger.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/infrastructure/drift_goal_store.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/application/health_status_providers.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_reader.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_health_read_store.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_plugin_gateway.dart';
import 'package:open_ring/features/health_sync/infrastructure/shared_preferences_health_write_preferences.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/heart/application/measure_controller.dart';
import 'package:open_ring/features/heart/infrastructure/drift_heart_history_reader.dart';
import 'package:open_ring/features/heart/infrastructure/drift_spot_reading_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/infrastructure/shared_preferences_module_store.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/onboarding/infrastructure/device_app_permissions.dart';
import 'package:open_ring/features/onboarding/infrastructure/method_channel_app_permissions.dart';
import 'package:open_ring/features/onboarding/infrastructure/shared_preferences_onboarding_store.dart';
import 'package:open_ring/features/open_score/application/celebration_providers.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/application/week_goal_providers.dart';
import 'package:open_ring/features/open_score/infrastructure/drift_day_tag_store.dart';
import 'package:open_ring/features/open_score/infrastructure/shared_preferences_celebration_store.dart';
import 'package:open_ring/features/open_score/infrastructure/shared_preferences_week_goal_store.dart';
import 'package:open_ring/features/ring/application/auto_measurements_controller.dart';
import 'package:open_ring/features/ring/application/pair_controller.dart';
import 'package:open_ring/features/ring/application/resume_sync_trigger.dart';
import 'package:open_ring/features/ring/application/ring_alert_providers.dart';
import 'package:open_ring/features/ring/application/ring_link_providers.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/sync_alerts.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/infrastructure/background_sync_signal.dart';
import 'package:open_ring/features/ring/infrastructure/drift_paired_ring_store.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:open_ring/features/ring/infrastructure/flutter_blue_plus_radio.dart';
import 'package:open_ring/features/ring/infrastructure/flutter_blue_plus_scanner.dart';
import 'package:open_ring/features/ring/infrastructure/flutter_blue_plus_transport.dart';
import 'package:open_ring/features/ring/infrastructure/method_channel_ring_notifier.dart';
import 'package:open_ring/features/ring/infrastructure/shared_preferences_ring_alert_preferences.dart';
import 'package:open_ring/features/ring/infrastructure/shared_preferences_sync_interval_store.dart';
import 'package:open_ring/features/ring/infrastructure/sync_locks_dao.dart';
import 'package:open_ring/features/ring/infrastructure/workmanager_sync_scheduler.dart';
import 'package:open_ring/features/settings/application/delete_all_data_controller.dart';
import 'package:open_ring/features/settings/application/notification_providers.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/infrastructure/device_local_data_eraser.dart';
import 'package:open_ring/features/settings/infrastructure/drift_user_profile_store.dart';
import 'package:open_ring/features/settings/infrastructure/legacy_preferences.dart';
import 'package:open_ring/features/settings/infrastructure/platform_notification_access.dart';
import 'package:open_ring/features/settings/infrastructure/shared_preferences_unit_system_store.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_imported_sleep_reader.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_rem_reporting_reader.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_sleep_history_reader.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/infrastructure/drift_ring_status_reader.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/infrastructure/drift_projection_store.dart';
import 'package:open_ring/features/widgets/application/widget_providers.dart';
import 'package:open_ring/features/widgets/infrastructure/home_widget_plugin_gateway.dart';
import 'package:open_ring/features/widgets/infrastructure/shared_preferences_today_widget_config_store.dart';
import 'package:open_ring/features/workout/application/location_access_provider.dart';
import 'package:open_ring/features/workout/application/workout_alert_providers.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/application/workout_lock_providers.dart';
import 'package:open_ring/features/workout/application/workout_recovery.dart';
import 'package:open_ring/features/workout/infrastructure/drift_imported_workout_reader.dart';
import 'package:open_ring/features/workout/infrastructure/drift_open_workout_store.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_history_reader.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_rating_store.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_store.dart';
import 'package:open_ring/features/workout/infrastructure/geolocator_location_source.dart';
import 'package:open_ring/features/workout/infrastructure/isolate_live_workout_registry.dart';
import 'package:open_ring/features/workout/infrastructure/method_channel_workout_notifier.dart';
import 'package:open_ring/features/workout/infrastructure/ring_live_heart_rate_source.dart';
import 'package:open_ring/features/workout/infrastructure/shared_preferences_workout_alert_preferences.dart';
import 'package:open_ring/features/workout/infrastructure/shared_preferences_workout_lock_preferences.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:path_provider/path_provider.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureAndroidPhotoPicker();
  await FlutterBluePlusTransport.enableStateRestoration();
  await clearLegacyPreferences();
  final themeModeStore = await SharedPreferencesThemeModeStore.open();
  final syncIntervalStore = await SharedPreferencesSyncIntervalStore.open();
  final onboardingStore = await SharedPreferencesOnboardingStore.open();
  final demoModeStore = await SharedPreferencesDemoModeStore.open();
  final widgetConfigStore =
      await SharedPreferencesTodayWidgetConfigStore.open();
  final documents = await getApplicationDocumentsDirectory();
  await PendingRestore(documents).applyIfPending(
    BackupArchive(documents: documents, appSchemaVersion: appSchemaVersion),
  );
  final database = openAppDatabase();
  final healthWriter = HealthPluginGateway.writer();
  final healthReader = HealthPluginGateway.reader();
  final container = ProviderContainer(
    overrides: [
      widgetGatewayProvider.overrideWithValue(
        HomeWidgetPluginGateway.forPlatform(),
      ),
      todayWidgetConfigStoreProvider.overrideWithValue(widgetConfigStore),
      backupDocumentsProvider.overrideWithValue(documents),
      themeModeStoreProvider.overrideWithValue(themeModeStore),
      onboardingStoreProvider.overrideWithValue(onboardingStore),
      demoModeStoreProvider.overrideWithValue(demoModeStore),
      demoDataStoreProvider.overrideWith(
        (ref) => DriftDemoDataStore(ref.watch(appDatabaseProvider)),
      ),
      appPermissionsProvider.overrideWith(
        (ref) => DeviceAppPermissions(
          platform: const MethodChannelAppPermissions(),
          battery: ref.watch(batterySettingsProvider),
          location: ref.watch(locationAccessProvider),
        ),
      ),
      bluetoothRadioProvider.overrideWithValue(const FlutterBluePlusRadio()),
      pairedRingStoreProvider.overrideWith(
        (ref) => DriftPairedRingStore(ref.watch(appDatabaseProvider)),
      ),
      userProfileStoreProvider.overrideWith(
        (ref) => DriftUserProfileStore(ref.watch(appDatabaseProvider)),
      ),
      unitSystemStoreProvider.overrideWithValue(
        SharedPreferencesUnitSystemStore(),
      ),
      moduleStoreProvider.overrideWithValue(SharedPreferencesModuleStore()),
      hideNumbersStoreProvider.overrideWithValue(
        SharedPreferencesHideNumbersStore(),
      ),
      workoutLockPreferencesProvider.overrideWithValue(
        SharedPreferencesWorkoutLockPreferences(),
      ),
      workoutAlertPreferencesProvider.overrideWithValue(
        SharedPreferencesWorkoutAlertPreferences(),
      ),
      weekGoalStoreProvider.overrideWithValue(SharedPreferencesWeekGoalStore()),
      celebrationStoreProvider.overrideWithValue(
        SharedPreferencesCelebrationStore(),
      ),
      weighInStoreProvider.overrideWith(
        (ref) => DriftWeighInStore(ref.watch(appDatabaseProvider)),
      ),
      dayTagStoreProvider.overrideWith(
        (ref) => DriftDayTagStore(ref.watch(appDatabaseProvider)),
      ),
      stepGoalHistoryProvider.overrideWith(
        (ref) => DriftStepGoalHistory(ref.watch(appDatabaseProvider)),
      ),
      goalStoreProvider.overrideWith(
        (ref) => DriftGoalStore(ref.watch(appDatabaseProvider)),
      ),
      projectionStoreProvider.overrideWith(
        (ref) => DriftProjectionStore(ref.watch(appDatabaseProvider)),
      ),
      mealStoreProvider.overrideWith(
        (ref) => DriftMealStore(ref.watch(appDatabaseProvider)),
      ),
      driftMealAnalysisStoreOverride,
      foodEnergyStoreProvider.overrideWithValue(
        SharedPreferencesFoodEnergyStore(),
      ),
      photoStoreProvider.overrideWithValue(IoPhotoStore.documents()),
      mealCameraProvider.overrideWithValue(
        ImagePickerMealCamera(ImagePicker()),
      ),
      mealGalleryProvider.overrideWithValue(
        ImagePickerMealGallery(ImagePicker()),
      ),
      ringAlertPreferencesProvider.overrideWithValue(
        SharedPreferencesRingAlertPreferences(),
      ),
      ringNotifierProvider.overrideWithValue(const MethodChannelRingNotifier()),
      workoutNotifierProvider.overrideWithValue(MethodChannelWorkoutNotifier()),
      healthWritePreferencesProvider.overrideWithValue(
        SharedPreferencesHealthWritePreferences(),
      ),
      notificationAccessProvider.overrideWith(
        (ref) => PlatformNotificationAccess(ref.watch(appPermissionsProvider)),
      ),
      localDataEraserProvider.overrideWith(
        (ref) => DeviceLocalDataEraser(
          ref.watch(appDatabaseProvider),
          ref.watch(photoStoreProvider),
          secrets: ref.watch(secretStoreProvider),
        ),
      ),
      secretStoreProvider.overrideWithValue(const SecureStorageSecretStore()),
      aiConfigStoreProvider.overrideWithValue(SharedPreferencesAiConfigStore()),
      aiRunMarkerStoreProvider.overrideWithValue(
        SharedPreferencesAiRunMarkerStore(),
      ),
      aiReportStoreProvider.overrideWith(
        (ref) => DriftAiReportStore(ref.watch(appDatabaseProvider)),
      ),
      appDatabaseProvider.overrideWithValue(database),
      syncStoreProvider.overrideWith(
        (ref) => DriftSyncStore(ref.watch(appDatabaseProvider)),
      ),
      syncLockProvider.overrideWith(
        (ref) => SyncLocksDao(ref.watch(appDatabaseProvider)),
      ),
      backgroundSyncFinishedProvider.overrideWithValue(
        backgroundSyncFinishedEvents(),
      ),
      syncIntervalStoreProvider.overrideWithValue(syncIntervalStore),
      syncSchedulerProvider.overrideWithValue(
        WorkmanagerSyncScheduler.forPlatform(backgroundSyncDispatcher),
      ),
      bleTransportProvider.overrideWith((ref) => FlutterBluePlusTransport()),
      ringScannerProvider.overrideWithValue(FlutterBluePlusScanner()),
      healthWriterProvider.overrideWith((ref) {
        if (ref.watch(demoModeProvider)) return const UnavailableHealthWriter();
        return healthWriter;
      }),
      healthReaderProvider.overrideWith((ref) {
        if (ref.watch(demoModeProvider)) return const UnavailableHealthReader();
        return healthReader;
      }),
      healthReadStoreProvider.overrideWith(
        (ref) => DriftHealthReadStore(ref.watch(appDatabaseProvider)),
      ),
      importedSleepReaderProvider.overrideWith(
        (ref) => DriftImportedSleepReader(ref.watch(appDatabaseProvider)),
      ),
      sleepHistoryReaderProvider.overrideWith(
        (ref) => DriftSleepHistoryReader(ref.watch(appDatabaseProvider)),
      ),
      remReportingReaderProvider.overrideWith(
        (ref) => DriftRemReportingReader(ref.watch(appDatabaseProvider)),
      ),
      heartHistoryReaderProvider.overrideWith(
        (ref) => DriftHeartHistoryReader(ref.watch(appDatabaseProvider)),
      ),
      activityHistoryReaderProvider.overrideWith(
        (ref) => DriftActivityHistoryReader(ref.watch(appDatabaseProvider)),
      ),
      ringStatusReaderProvider.overrideWith(
        (ref) => DriftRingStatusReader(ref.watch(appDatabaseProvider)),
      ),
      spotReadingStoreProvider.overrideWith(
        (ref) => DriftSpotReadingStore(ref.watch(appDatabaseProvider)),
      ),
      workoutStoreProvider.overrideWith((ref) {
        final database = ref.watch(appDatabaseProvider);
        if (ref.watch(demoModeProvider)) return DemoWorkoutStore(database);
        return DriftWorkoutStore(database);
      }),
      openWorkoutStoreProvider.overrideWith(
        (ref) => DriftOpenWorkoutStore(ref.watch(appDatabaseProvider)),
      ),
      liveWorkoutRegistryProvider.overrideWithValue(
        IsolateLiveWorkoutRegistry(),
      ),
      workoutRecoveryLabelsProvider.overrideWith(
        (ref) => workoutLocationNotice(ringAlertStrings()).live,
      ),
      workoutRatingStoreProvider.overrideWith(
        (ref) => DriftWorkoutRatingStore(ref.watch(appDatabaseProvider)),
      ),
      workoutHistoryReaderProvider.overrideWith(
        (ref) => DriftWorkoutHistoryReader(ref.watch(appDatabaseProvider)),
      ),
      importedWorkoutReaderProvider.overrideWith(
        (ref) => DriftImportedWorkoutReader(ref.watch(appDatabaseProvider)),
      ),
      locationSourceProvider.overrideWithValue(GeolocatorLocationSource()),
      liveHeartRateSourceProvider.overrideWith((ref) {
        if (ref.watch(demoModeProvider)) return const NoRingHeartRateSource();
        return RingLiveHeartRateSource(
          driver: ref.watch(smartRingDriverProvider),
          store: ref.watch(syncStoreProvider),
          lock: ref.watch(syncLockProvider),
          clock: ref.watch(syncClockProvider),
        );
      }),
    ],
  );
  if (!demoModeStore.enabled) {
    unawaited(container.read(syncIntervalProvider.notifier).ensureScheduled());
  }
  unawaited(container.read(resumeSyncTriggerProvider).onForeground());
  unawaited(container.read(mealRecoveryProvider.notifier).run());
  unawaited(container.read(workoutRecoveryProvider.notifier).run());
  unawaited(container.read(aiRunRecoveryProvider.future).catchError((_) {}));
  container
    ..listen(healthGrantRetryProvider, (_, _) {})
    ..listen(dayRollProvider, (_, _) {})
    ..listen(goalReviewTriggerProvider, (_, _) {})
    ..listen(mealAnalysisTriggerProvider, (_, _) {});
  startWidgetPush(container);
  runApp(
    UncontrolledProviderScope(container: container, child: const OpenRingApp()),
  );
}
