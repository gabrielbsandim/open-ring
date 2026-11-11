import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/background/background_sync_dispatcher.dart';
import 'package:open_ring/app/theme/shared_preferences_theme_mode_store.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/core/database/app_database_provider.dart';
import 'package:open_ring/core/database/open_app_database.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/infrastructure/drift_activity_history_reader.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/application/health_status_providers.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_health_read_store.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_plugin_gateway.dart';
import 'package:open_ring/features/health_sync/infrastructure/shared_preferences_health_write_preferences.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/heart/application/measure_controller.dart';
import 'package:open_ring/features/heart/infrastructure/drift_heart_history_reader.dart';
import 'package:open_ring/features/heart/infrastructure/drift_spot_reading_store.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/onboarding/infrastructure/device_app_permissions.dart';
import 'package:open_ring/features/onboarding/infrastructure/method_channel_app_permissions.dart';
import 'package:open_ring/features/onboarding/infrastructure/shared_preferences_onboarding_store.dart';
import 'package:open_ring/features/ring/application/auto_measurements_controller.dart';
import 'package:open_ring/features/ring/application/pair_controller.dart';
import 'package:open_ring/features/ring/application/protocol_lab_controller.dart';
import 'package:open_ring/features/ring/application/resume_sync_trigger.dart';
import 'package:open_ring/features/ring/application/ring_alert_providers.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/infrastructure/background_sync_signal.dart';
import 'package:open_ring/features/ring/infrastructure/drift_paired_ring_store.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:open_ring/features/ring/infrastructure/flutter_blue_plus_radio.dart';
import 'package:open_ring/features/ring/infrastructure/flutter_blue_plus_scanner.dart';
import 'package:open_ring/features/ring/infrastructure/flutter_blue_plus_transport.dart';
import 'package:open_ring/features/ring/infrastructure/method_channel_ring_notifier.dart';
import 'package:open_ring/features/ring/infrastructure/share_plus_session_log_exporter.dart';
import 'package:open_ring/features/ring/infrastructure/shared_preferences_ring_alert_preferences.dart';
import 'package:open_ring/features/ring/infrastructure/shared_preferences_sync_interval_store.dart';
import 'package:open_ring/features/ring/infrastructure/sync_locks_dao.dart';
import 'package:open_ring/features/ring/infrastructure/workmanager_sync_scheduler.dart';
import 'package:open_ring/features/settings/application/app_language_controller.dart';
import 'package:open_ring/features/settings/application/delete_all_data_controller.dart';
import 'package:open_ring/features/settings/application/notification_providers.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/infrastructure/device_local_data_eraser.dart';
import 'package:open_ring/features/settings/infrastructure/drift_user_profile_store.dart';
import 'package:open_ring/features/settings/infrastructure/platform_notification_access.dart';
import 'package:open_ring/features/settings/infrastructure/shared_preferences_app_language_store.dart';
import 'package:open_ring/features/settings/infrastructure/shared_preferences_unit_system_store.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_imported_sleep_reader.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_rem_reporting_reader.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_sleep_history_reader.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/infrastructure/drift_ring_status_reader.dart';
import 'package:open_ring/features/widgets/application/widget_providers.dart';
import 'package:open_ring/features/widgets/infrastructure/home_widget_plugin_gateway.dart';
import 'package:open_ring/features/widgets/infrastructure/shared_preferences_today_widget_config_store.dart';
import 'package:open_ring/features/workout/application/location_access_provider.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/infrastructure/drift_imported_workout_reader.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_history_reader.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_store.dart';
import 'package:open_ring/features/workout/infrastructure/geolocator_location_source.dart';
import 'package:open_ring/features/workout/infrastructure/ring_live_heart_rate_source.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterBluePlusTransport.enableStateRestoration();
  final themeModeStore = await SharedPreferencesThemeModeStore.open();
  final syncIntervalStore = await SharedPreferencesSyncIntervalStore.open();
  final onboardingStore = await SharedPreferencesOnboardingStore.open();
  final appLanguageStore = await SharedPreferencesAppLanguageStore.open();
  final widgetConfigStore =
      await SharedPreferencesTodayWidgetConfigStore.open();
  final database = openAppDatabase();
  final container = ProviderContainer(
    overrides: [
      widgetGatewayProvider.overrideWithValue(
        HomeWidgetPluginGateway.forPlatform(),
      ),
      todayWidgetConfigStoreProvider.overrideWithValue(widgetConfigStore),
      themeModeStoreProvider.overrideWithValue(themeModeStore),
      onboardingStoreProvider.overrideWithValue(onboardingStore),
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
      appLanguageStoreProvider.overrideWithValue(appLanguageStore),
      ringAlertPreferencesProvider.overrideWithValue(
        SharedPreferencesRingAlertPreferences(),
      ),
      ringNotifierProvider.overrideWithValue(const MethodChannelRingNotifier()),
      healthWritePreferencesProvider.overrideWithValue(
        SharedPreferencesHealthWritePreferences(),
      ),
      notificationAccessProvider.overrideWith(
        (ref) => PlatformNotificationAccess(ref.watch(appPermissionsProvider)),
      ),
      localDataEraserProvider.overrideWith(
        (ref) => DeviceLocalDataEraser(ref.watch(appDatabaseProvider)),
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
      healthWriterProvider.overrideWithValue(HealthPluginGateway.writer()),
      healthReaderProvider.overrideWithValue(HealthPluginGateway.reader()),
      healthReadStoreProvider.overrideWith(
        (ref) => DriftHealthReadStore(ref.watch(appDatabaseProvider)),
      ),
      importedSleepReaderProvider.overrideWith(
        (ref) => DriftImportedSleepReader(ref.watch(appDatabaseProvider)),
      ),
      sessionLogExporterProvider.overrideWithValue(
        const SharePlusSessionLogExporter(),
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
      workoutStoreProvider.overrideWith(
        (ref) => DriftWorkoutStore(ref.watch(appDatabaseProvider)),
      ),
      workoutHistoryReaderProvider.overrideWith(
        (ref) => DriftWorkoutHistoryReader(ref.watch(appDatabaseProvider)),
      ),
      importedWorkoutReaderProvider.overrideWith(
        (ref) => DriftImportedWorkoutReader(ref.watch(appDatabaseProvider)),
      ),
      locationSourceProvider.overrideWithValue(GeolocatorLocationSource()),
      liveHeartRateSourceProvider.overrideWith(
        (ref) => RingLiveHeartRateSource(
          driver: ref.watch(smartRingDriverProvider),
          store: ref.watch(syncStoreProvider),
          lock: ref.watch(syncLockProvider),
          clock: ref.watch(syncClockProvider),
        ),
      ),
    ],
  );
  unawaited(container.read(syncIntervalProvider.notifier).ensureScheduled());
  unawaited(container.read(resumeSyncTriggerProvider).onForeground());
  container.listen(healthGrantRetryProvider, (_, _) {});
  startWidgetPush(container);
  runApp(
    UncontrolledProviderScope(container: container, child: const OpenRingApp()),
  );
}
