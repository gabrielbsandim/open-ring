import 'dart:ui';

import 'package:open_ring/app/background/background_sync_alerts.dart';
import 'package:open_ring/app/background/background_sync_runner.dart';
import 'package:open_ring/app/background/background_widget_publish.dart';
import 'package:open_ring/core/database/open_app_database.dart';
import 'package:open_ring/features/demo/infrastructure/shared_preferences_demo_mode_store.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_plugin_gateway.dart';
import 'package:open_ring/features/health_sync/infrastructure/shared_preferences_health_write_preferences.dart';
import 'package:open_ring/features/ring/application/sync_alerts.dart';
import 'package:open_ring/features/ring/application/sync_paired_ring.dart';
import 'package:open_ring/features/ring/infrastructure/background_sync_signal.dart';
import 'package:open_ring/features/ring/infrastructure/flutter_blue_plus_transport.dart';
import 'package:open_ring/features/ring/infrastructure/method_channel_ring_notifier.dart';
import 'package:open_ring/features/ring/infrastructure/method_channel_sync_service.dart';
import 'package:open_ring/features/ring/infrastructure/shared_preferences_ring_alert_preferences.dart';
import 'package:open_ring/features/widgets/infrastructure/home_widget_plugin_gateway.dart';
import 'package:ring_driver/ring_driver.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) {
    DartPluginRegistrant.ensureInitialized();
    return runBackgroundSync();
  });
}

// Always reports success: a ring out of range is the usual failure, and the
// next period retries it without a WorkManager backoff draining the battery.
Future<bool> runBackgroundSync() {
  final database = openAppDatabase();
  final driver = ColmiDriver(transport: FlutterBluePlusTransport());
  const service = MethodChannelSyncService();
  SyncOutcome? outcome;
  return superviseBackgroundSync(
    demoMode: readStoredDemoMode,
    keepAlive: () async {
      final strings = ringAlertStrings();
      await service.start(
        channelName: strings.ringSyncServiceChannel,
        title: strings.ringSyncServiceTitle,
      );
    },
    sync: () async {
      outcome = await BackgroundSyncRunner(
        database: database,
        driver: driver,
        healthWriter: HealthPluginGateway.writer(),
        healthReader: HealthPluginGateway.reader(background: true),
        healthWrites: SharedPreferencesHealthWritePreferences(),
      ).run();
    },
    sendAlerts: () => sendBackgroundSyncAlerts(
      database: database,
      outcome: outcome,
      preferences: SharedPreferencesRingAlertPreferences(),
      notifier: const MethodChannelRingNotifier(),
    ),
    publishWidgets: () =>
        publishWidgetSnapshot(database, HomeWidgetPluginGateway.forPlatform()),
    announceFinished: announceBackgroundSyncFinished,
    teardown: [driver.close, database.close, service.stop],
  );
}
