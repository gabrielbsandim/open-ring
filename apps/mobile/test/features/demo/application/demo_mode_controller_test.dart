import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/database/app_database_provider.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/infrastructure/drift_activity_history_reader.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/body/infrastructure/drift_weigh_in_store.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/demo/infrastructure/drift_demo_data_store.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/heart/application/measure_controller.dart';
import 'package:open_ring/features/heart/application/measure_state.dart';
import 'package:open_ring/features/heart/infrastructure/drift_heart_history_reader.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/ring/application/resume_sync_trigger.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:open_ring/features/ring/infrastructure/sync_locks_dao.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_sleep_history_reader.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/infrastructure/drift_ring_status_reader.dart';
import 'package:open_ring/features/widgets/application/widget_providers.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_history_reader.dart';

import '../../../helpers/database.dart';
import '../../../helpers/demo_fakes.dart';
import '../../../helpers/fake_health_reader.dart';
import '../../../helpers/fake_health_writer.dart';
import '../../../helpers/fake_ring_driver.dart';
import '../../../helpers/fake_sync_scheduler.dart';
import '../../../helpers/in_memory_theme_mode_store.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';
import '../../../helpers/sync_fixtures.dart';
import '../../../helpers/widget_fakes.dart';

final now = DateTime(2026, 11, 11, 14, 37);

final class Harness {
  new({bool demo = false, List<Override> overrides = const []})
    : store = InMemoryDemoModeStore(enabled: demo),
      onboarding = InMemoryOnboardingStore(completed: demo) {
    container = ProviderContainer.test(
      overrides: [
        clockProvider.overrideWithValue(() => now),
        onboardingStoreProvider.overrideWithValue(onboarding),
        ...demoOverrides(store: store, data: data),
        ...ringOverrides(
          store: syncStore,
          scheduler: scheduler,
          driver: driver,
          clock: () => now,
        ),
        ...overrides,
      ],
    );
  }

  final InMemoryDemoModeStore store;
  final InMemoryOnboardingStore onboarding;
  final data = RecordingDemoDataStore();
  final scheduler = FakeSyncScheduler();
  final driver = FakeRingDriver();
  final syncStore = FakeSyncStore(
    ring: PairedRing(
      deviceId: 'DEMO-RING-0000',
      lastSyncAt: DateTime(2026, 11, 11, 9),
    ),
  );
  late final ProviderContainer container;

  DemoModeController get demo => container.read(demoModeProvider.notifier);

  bool get enabled => container.read(demoModeProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('entering', () {
    test('saves the flag, seeds today and completes onboarding', () async {
      final harness = Harness();

      final entered = await harness.demo.enter();

      expect(entered, isTrue);
      expect(harness.enabled, isTrue);
      expect(harness.store.enabled, isTrue);
      expect(harness.onboarding.completed, isTrue);
      expect(harness.scheduler.cancels, 1);
      expect(harness.data.replaced.single.syncedAt, now);
      expect(harness.container.read(dataRevisionProvider), 1);
    });

    test('a failed seed leaves the demo and onboarding untouched', () async {
      final harness = Harness();
      harness.data.replaceError = StateError('disk full');

      final entered = await harness.demo.enter();

      expect(entered, isFalse);
      expect(harness.enabled, isFalse);
      expect(harness.store.enabled, isFalse);
      expect(harness.onboarding.completed, isFalse);
    });
  });

  group('leaving', () {
    test('deletes the demo data and reopens onboarding', () async {
      final harness = Harness(demo: true);

      final left = await harness.demo.leave();

      expect(left, isTrue);
      expect(harness.data.wipes, 1);
      expect(harness.enabled, isFalse);
      expect(harness.store.enabled, isFalse);
      expect(harness.onboarding.completed, isFalse);
    });

    test('a failed wipe keeps the demo running', () async {
      final harness = Harness(demo: true);
      harness.data.wipeError = StateError('database is locked');

      final left = await harness.demo.leave();

      expect(left, isFalse);
      expect(harness.enabled, isTrue);
      expect(harness.onboarding.completed, isTrue);
    });
  });

  group('while in the demo', () {
    test('a ring sync never reaches Bluetooth and renews the data', () async {
      final harness = Harness(demo: true);
      final sync = harness.container.read(ringSyncProvider.notifier);

      await sync.sync();
      await sync.autoSync();

      expect(harness.driver.calls, isEmpty);
      expect(harness.syncStore.saved, isEmpty);
      expect(harness.syncStore.runs, isEmpty);
      expect(harness.data.replaced, hasLength(2));
      expect(harness.container.read(ringSyncProvider).lastError, isNull);
    });

    test('coming back to the app never reaches Bluetooth', () async {
      final harness = Harness(demo: true);

      await harness.container.read(resumeSyncTriggerProvider).onForeground();

      expect(harness.driver.calls, isEmpty);
      expect(harness.data.replaced, hasLength(1));
    });

    test('a spot measure fails as no ring without Bluetooth', () async {
      final harness = Harness(demo: true);
      final container = harness.container..listen(measureProvider, (_, _) {});

      await container.read(measureProvider.notifier).start();

      final state = container.read(measureProvider);
      expect(state.phase, MeasurePhase.failed);
      expect(state.failure, MeasureFailure.noRing);
      expect(harness.driver.calls, isEmpty);
    });

    test('nothing is written to Health and the outbox waits', () async {
      final db = await pairedDatabase();
      final writer = FakeHealthWriter();
      final real = ProviderContainer.test(
        overrides: [
          syncStoreProvider.overrideWithValue(DriftSyncStore(db)),
          syncLockProvider.overrideWithValue(SyncLocksDao(db)),
          smartRingDriverProvider.overrideWithValue(loadedDriver()),
          syncClockProvider.overrideWithValue(() => syncNow),
        ],
      );
      await real.read(ringSyncProvider.notifier).sync();
      final pending = (await HealthOutboxDao(db).pending()).length;
      final harness = Harness(
        demo: true,
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          healthWriterProvider.overrideWithValue(writer),
        ],
      );
      final health = harness.container.read(healthSyncProvider.notifier);

      await health.process();
      final granted = await health.requestAccess();

      expect(pending, greaterThan(0));
      expect(granted, isFalse);
      expect(writer.requests, isEmpty);
      expect(writer.batches, isEmpty);
      expect(await HealthOutboxDao(db).pending(), hasLength(pending));
    });

    test('nothing is read from Health', () async {
      final reader = FakeHealthReader(access: HealthAccess.granted);
      final harness = Harness(
        demo: true,
        overrides: [
          healthReaderProvider.overrideWithValue(reader),
          healthReadStoreProvider.overrideWithValue(InMemoryHealthReadStore()),
        ],
      );
      final sleep = harness.container.read(healthReadProvider.notifier);
      await harness.container.read(healthReadProvider.future);

      await sleep.importNow();
      await sleep.setEnabled(enabled: true);
      await harness.container
          .read(healthReadsProvider(HealthRecordKind.workout).notifier)
          .importNow();

      expect(reader.reads, isEmpty);
      expect(reader.requests, isEmpty);
    });
  });

  test('entering and leaving demo updates v2 widget snapshots while preserving '
      'widget config', () async {
    final db = memoryDatabase();
    final gateway = FakeWidgetGateway();
    final customConfig = TodayWidgetConfig(
      metrics: const [
        WidgetMetric.dayScore,
        WidgetMetric.weight,
        WidgetMetric.energy,
        WidgetMetric.steps,
      ],
    );
    final configStore = InMemoryTodayWidgetConfigStore(customConfig);
    final c = ProviderContainer.test(
      overrides: [
        clockProvider.overrideWithValue(() => now),
        appDatabaseProvider.overrideWithValue(db),
        demoModeStoreProvider.overrideWithValue(InMemoryDemoModeStore()),
        demoDataStoreProvider.overrideWithValue(DriftDemoDataStore(db)),
        onboardingStoreProvider.overrideWithValue(InMemoryOnboardingStore()),
        syncSchedulerProvider.overrideWithValue(FakeSyncScheduler()),
        sleepHistoryReaderProvider.overrideWithValue(
          DriftSleepHistoryReader(db),
        ),
        heartHistoryReaderProvider.overrideWithValue(
          DriftHeartHistoryReader(db),
        ),
        activityHistoryReaderProvider.overrideWithValue(
          DriftActivityHistoryReader(db),
        ),
        ringStatusReaderProvider.overrideWithValue(DriftRingStatusReader(db)),
        workoutHistoryReaderProvider.overrideWithValue(
          DriftWorkoutHistoryReader(db),
        ),
        weighInStoreProvider.overrideWithValue(DriftWeighInStore(db)),
        widgetGatewayProvider.overrideWithValue(gateway),
        todayWidgetConfigStoreProvider.overrideWithValue(configStore),
        moduleStoreProvider.overrideWithValue(
          InMemoryModuleStore({
            ModuleId.openScore,
            ModuleId.body,
            ModuleId.energy,
            ModuleId.effort,
          }),
        ),
        hideNumbersStoreProvider.overrideWithValue(InMemoryHideNumbersStore()),
        userProfileStoreProvider.overrideWithValue(
          InMemoryUserProfileStore(fullProfile),
        ),
        themeModeStoreProvider.overrideWithValue(InMemoryThemeModeStore()),
        unitSystemStoreProvider.overrideWithValue(
          InMemoryUnitSystemStore(UnitSystem.metric),
        ),
      ],
    );
    final sub = startWidgetPush(c);
    addTearDown(sub.close);
    await c.read(enabledModulesProvider.future);
    await c.read(widgetSnapshotProvider.future);
    await pumpEventQueue();

    expect(gateway.snapshots.last['paired'], isFalse);
    expect(gateway.thisWeekAvailable.last, isTrue);

    expect(await c.read(demoModeProvider.notifier).enter(), isTrue);
    await c.read(widgetSnapshotProvider.future);
    await pumpEventQueue();

    expect(gateway.snapshots.last['paired'], isTrue);
    expect(gateway.snapshots.last['batteryPercent'], 76);
    expect(gateway.snapshots.last['dayScore'], isNotNull);
    expect(gateway.snapshots.last['weight'], isNotNull);
    expect(gateway.snapshots.last['effort'], isNotNull);
    expect(c.read(todayWidgetConfigProvider), customConfig);

    expect(await c.read(demoModeProvider.notifier).leave(), isTrue);
    await c.read(widgetSnapshotProvider.future);
    await pumpEventQueue();

    expect(gateway.snapshots.last['paired'], isFalse);
    expect(gateway.snapshots.last['batteryPercent'], isNull);
    expect(gateway.snapshots.last['weight'], isNull);
    expect(c.read(todayWidgetConfigProvider), customConfig);
  });
}
