import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/database/app_database_provider.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/infrastructure/drift_activity_history_reader.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_data.dart';
import 'package:open_ring/features/demo/domain/demo_data_generator.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/demo/infrastructure/demo_workout_store.dart';
import 'package:open_ring/features/demo/infrastructure/drift_demo_data_store.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_health_read_store.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/heart/application/measure_controller.dart';
import 'package:open_ring/features/heart/infrastructure/drift_heart_history_reader.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/ring/application/auto_measurements_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:open_ring/features/ring/infrastructure/sync_locks_dao.dart';
import 'package:open_ring/features/settings/application/about_providers.dart';
import 'package:open_ring/features/settings/application/delete_all_data_controller.dart';
import 'package:open_ring/features/settings/infrastructure/drift_user_profile_store.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_imported_sleep_reader.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_rem_reporting_reader.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_sleep_history_reader.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/infrastructure/drift_ring_status_reader.dart';
import 'package:open_ring/features/workout/application/location_access_provider.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/infrastructure/drift_imported_workout_reader.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_history_reader.dart';
import 'package:open_ring/features/workout/presentation/workout_routes.dart';
import 'package:ring_driver/ring_driver.dart';

import '../helpers/ble_fakes.dart';
import '../helpers/database.dart';
import '../helpers/fake_ring_driver.dart';
import '../helpers/fake_sync_scheduler.dart';
import '../helpers/in_memory_sync_interval_store.dart';
import '../helpers/in_memory_theme_mode_store.dart';
import '../helpers/onboarding_fakes.dart';
import '../helpers/ring_fakes.dart';
import '../helpers/settings_fakes.dart';
import '../helpers/workout_fakes.dart';
import 'rgb_png.dart';

// Renders the Play listing graphics only when asked, e.g.
// OPEN_RING_STORE_DIR=/tmp/store flutter test test/store
final String? outputDir = Platform.environment['OPEN_RING_STORE_DIR'];

final now = DateTime(2026, 11, 11, 18, 20);
const phone = Size(1080, 2160);
const phoneRatio = 2.625;
const featureGraphic = Size(1024, 500);
const tagline = 'Seu anel inteligente, seus dados,\nsem nuvem';
const iconPath = 'fastlane/metadata/android/en-US/images/icon.png';
const captureKey = Key('store_capture');

Directory materialFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    return Directory('$root/bin/cache/artifacts/material_fonts');
  }
  final engine = File(Platform.resolvedExecutable).parent.parent;
  return Directory('${engine.parent.path}/material_fonts');
}

Future<void> loadFonts() async {
  final fonts = materialFonts();
  final roboto = FontLoader('Roboto');
  for (final weight in ['Light', 'Regular', 'Medium', 'Bold', 'Black']) {
    final bytes = File('${fonts.path}/Roboto-$weight.ttf').readAsBytesSync();
    roboto.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  final icons = File('${fonts.path}/MaterialIcons-Regular.otf');
  final material = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
  await roboto.load();
  await material.load();
}

Future<void> capture(WidgetTester tester, String name, double ratio) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    final rgba = await image.toByteData();
    final png = encodeRgbPng(rgba!, width: image.width, height: image.height);
    image.dispose();
    File('$outputDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png);
  });
}

// A month of history fills the 30 day trend, and the ring gets a factory
// style name so no screen reads as a demo.
DemoData storeData() {
  final data = DemoDataGenerator(now: now, days: 30).generate();
  return DemoData(
    identity: const RingIdentity(
      deviceId: demoDeviceId,
      name: 'R09_C0FE',
      model: 'R09',
    ),
    pairedAt: data.pairedAt,
    syncedAt: data.syncedAt,
    battery: data.battery,
    activity: data.activity,
    heartRate: data.heartRate,
    hrv: data.hrv,
    spo2: data.spo2,
    stress: data.stress,
    sleep: data.sleep,
    workouts: data.workouts,
    syncRuns: data.syncRuns,
  );
}

List<Override> appOverrides(AppDatabase db) => [
  clockProvider.overrideWithValue(() => now),
  syncClockProvider.overrideWithValue(() => now),
  themeModeStoreProvider.overrideWithValue(
    InMemoryThemeModeStore(ThemeMode.light),
  ),
  onboardingStoreProvider.overrideWithValue(
    InMemoryOnboardingStore(completed: true),
  ),
  // Off, so the shell drops the demo strip the way a paired ring shows it.
  demoModeStoreProvider.overrideWithValue(InMemoryDemoModeStore()),
  demoDataStoreProvider.overrideWithValue(DriftDemoDataStore(db)),
  ...bleOverrides(),
  smartRingDriverProvider.overrideWithValue(FakeRingDriver()),
  syncIntervalStoreProvider.overrideWithValue(InMemorySyncIntervalStore()),
  syncSchedulerProvider.overrideWithValue(FakeSyncScheduler()),
  batterySettingsProvider.overrideWithValue(FakeBatterySettings()),
  spotReadingStoreProvider.overrideWithValue(RecordingSpotStore()),
  ...onboardingOverrides(profileStore: DriftUserProfileStore(db)),
  appDatabaseProvider.overrideWithValue(db),
  appVersionProvider.overrideWith((ref) async => '0.2.0'),
  localDataEraserProvider.overrideWithValue(FakeLocalDataEraser()),
  syncStoreProvider.overrideWithValue(DriftSyncStore(db)),
  syncLockProvider.overrideWithValue(SyncLocksDao(db)),
  healthReadStoreProvider.overrideWithValue(DriftHealthReadStore(db)),
  importedSleepReaderProvider.overrideWithValue(DriftImportedSleepReader(db)),
  sleepHistoryReaderProvider.overrideWithValue(DriftSleepHistoryReader(db)),
  remReportingReaderProvider.overrideWithValue(DriftRemReportingReader(db)),
  heartHistoryReaderProvider.overrideWithValue(DriftHeartHistoryReader(db)),
  activityHistoryReaderProvider.overrideWithValue(
    DriftActivityHistoryReader(db),
  ),
  ringStatusReaderProvider.overrideWithValue(DriftRingStatusReader(db)),
  workoutStoreProvider.overrideWithValue(DemoWorkoutStore(db)),
  workoutHistoryReaderProvider.overrideWithValue(DriftWorkoutHistoryReader(db)),
  importedWorkoutReaderProvider.overrideWithValue(
    DriftImportedWorkoutReader(db),
  ),
  locationAccessProvider.overrideWithValue(FakeLocationAccess()),
  locationSourceProvider.overrideWithValue(FakeLocationSource()),
  liveHeartRateSourceProvider.overrideWithValue(const NoRingHeartRateSource()),
];

void main() {
  testWidgets('renders the phone screenshots from demo data', (tester) async {
    await tester.runAsync(loadFonts);
    final db = memoryDatabase();
    final workouts = await tester.runAsync(() async {
      await DriftDemoDataStore(db).replace(storeData());
      return await DriftWorkoutHistoryReader(db).recent(limit: 1);
    });
    tester.view
      ..devicePixelRatio = phoneRatio
      ..physicalSize = phone;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = [const Locale('pt', 'BR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: ProviderScope(
          overrides: appOverrides(db),
          child: const OpenRingApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final router = ProviderScope.containerOf(
      tester.element(find.byType(OpenRingApp)),
    ).read(appRouterProvider);

    final screens = {
      '1_today': AppTab.today.path,
      '2_sleep': AppTab.sleep.path,
      '3_heart': AppTab.heart.path,
      '4_activity': AppTab.activity.path,
      '5_workout': workoutSummaryPath(workouts!.first.id),
      '6_trends': AppPaths.trends,
      '7_readiness': AppPaths.readiness,
      '8_ring': AppTab.ring.path,
    };
    for (final MapEntry(key: name, value: path) in screens.entries) {
      router.go(path);
      await tester.pumpAndSettle();
      await capture(tester, name, phoneRatio);
    }
  }, skip: outputDir == null);

  testWidgets('renders the feature graphic', (tester) async {
    await tester.runAsync(loadFonts);
    final icon = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
        File(iconPath).readAsBytesSync(),
      );
      return (await codec.getNextFrame()).image;
    });
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = featureGraphic;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FeatureGraphic(icon: icon!),
        ),
      ),
    );
    await capture(tester, 'feature_graphic', 1);
    icon.dispose();
  }, skip: outputDir == null);
}

class FeatureGraphic extends StatelessWidget {
  const new({required this.icon, super.key});

  final ui.Image icon;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.9, -0.6),
          radius: 1.4,
          colors: [Color(0xFF221B3A), Color(0xFF0E0F13)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 72),
        child: Row(
          children: [
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(48),
                border: Border.all(color: colors.strongBorder, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(48),
                child: RawImage(image: icon, width: 220, height: 220),
              ),
            ),
            const SizedBox(width: 56),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OpenRing',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 84,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.5,
                      height: 1,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    tagline,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 32,
                      height: 1.25,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      for (final (label, color) in [
                        ('Sono', colors.sleep),
                        ('Coração', colors.heart),
                        ('Atividade', colors.activity),
                        ('Oxigênio', colors.oxygen),
                      ]) ...[
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: colors.textLabel,
                          ),
                        ),
                        const SizedBox(width: 24),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
