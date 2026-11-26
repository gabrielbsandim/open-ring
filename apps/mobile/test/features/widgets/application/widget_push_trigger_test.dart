import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/widgets/application/widget_providers.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../../../helpers/in_memory_theme_mode_store.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/settings_fakes.dart';
import '../../../helpers/widget_fakes.dart';

typedef Rig = ({
  ProviderContainer container,
  FakeWidgetGateway gateway,
  MutableRingStatusReader ring,
  InMemoryTodayWidgetConfigStore configs,
  ListedWorkouts workouts,
});

final class ListedWorkouts implements WorkoutHistoryReader {
  List<WorkoutListItem> items = [];

  @override
  Future<List<WorkoutListItem>> recent({required int limit}) async =>
      items.take(limit).toList();

  @override
  Future<SavedWorkout?> byId(int id) async => null;

  @override
  Future<List<WorkoutListItem>> intersecting({
    required DateTime from,
    required DateTime to,
  }) async => [
    for (final item in items)
      if (item.end.isAfter(from) && item.start.isBefore(to)) item,
  ]..sort((a, b) => a.start.compareTo(b.start));

  @override
  Future<List<SavedWorkout>> routed({
    required DateTime from,
    required DateTime to,
    required Set<WorkoutType> types,
  }) async => const [];
}

Rig rig({
  UnitSystem units = UnitSystem.metric,
  Set<ModuleId> modules = const {},
  bool hideNumbers = false,
  TodayWidgetConfig? config,
  UserProfile? profile,
}) {
  final scenario = fullDataScenario;
  final gateway = FakeWidgetGateway();
  final ring = MutableRingStatusReader(freshRing);
  final configs = InMemoryTodayWidgetConfigStore(config);
  final workouts = ListedWorkouts();
  final container = ProviderContainer.test(
    overrides: [
      clockProvider.overrideWithValue(() => metricsNow),
      sleepHistoryReaderProvider.overrideWithValue(
        FakeSleepHistoryReader(scenario.spans),
      ),
      heartHistoryReaderProvider.overrideWithValue(scenario.heart),
      activityHistoryReaderProvider.overrideWithValue(
        FakeActivityHistoryReader(scenario.activity, slots: scenario.slots),
      ),
      ringStatusReaderProvider.overrideWithValue(ring),
      themeModeStoreProvider.overrideWithValue(InMemoryThemeModeStore()),
      widgetGatewayProvider.overrideWithValue(gateway),
      todayWidgetConfigStoreProvider.overrideWithValue(configs),
      workoutHistoryReaderProvider.overrideWithValue(workouts),
      unitSystemStoreProvider.overrideWithValue(InMemoryUnitSystemStore(units)),
      moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
      hideNumbersStoreProvider.overrideWithValue(
        InMemoryHideNumbersStore(hidden: hideNumbers),
      ),
      userProfileStoreProvider.overrideWithValue(
        InMemoryUserProfileStore(profile),
      ),
    ],
  );
  return (
    container: container,
    gateway: gateway,
    ring: ring,
    configs: configs,
    workouts: workouts,
  );
}

Future<void> settle(ProviderContainer container) async {
  await container.read(widgetSnapshotProvider.future);
  await pumpEventQueue();
}

void main() {
  test(
    'starting the trigger publishes the snapshot and the appearance',
    () async {
      final r = rig();

      startWidgetPush(r.container);
      await settle(r.container);

      expect(r.gateway.snapshots, hasLength(1));
      expect(r.gateway.snapshots.single['steps'], 2224);
      expect(r.gateway.snapshots.single['batteryPercent'], 68);
      expect(r.gateway.appearances.single, {
        'appTheme': 'system',
        'todayTheme': 'app',
        'todayMetrics': ['sleep', 'steps', 'heartRate'],
        'units': 'metric',
      });
    },
  );

  test('a data revision with new data publishes again', () async {
    final r = rig();
    startWidgetPush(r.container);
    await settle(r.container);

    r.ring.value = RingStatus(
      paired: true,
      lastSyncAt: metricsNow,
      batteryPercent: 61,
    );
    r.container.read(dataRevisionProvider.notifier).bump();
    await settle(r.container);

    expect(r.gateway.snapshots, hasLength(2));
    expect(r.gateway.snapshots.last['batteryPercent'], 61);
    expect(
      r.gateway.snapshots.last['syncedAtMs'],
      metricsNow.millisecondsSinceEpoch,
    );
  });

  test('a data revision with the same data publishes nothing', () async {
    final r = rig();
    startWidgetPush(r.container);
    await settle(r.container);

    r.container.read(dataRevisionProvider.notifier).bump();
    await settle(r.container);

    expect(r.gateway.snapshots, hasLength(1));
  });

  test('a theme or widget config change publishes the appearance', () async {
    final r = rig();
    startWidgetPush(r.container);
    await settle(r.container);

    await r.container.read(themeModeProvider.notifier).select(ThemeMode.dark);
    await pumpEventQueue();
    final config = r.container.read(todayWidgetConfigProvider.notifier);
    for (final change in [
      () => config.toggle(WidgetMetric.spo2),
      () => config.toggle(WidgetMetric.sleep),
      () => config.selectTheme(WidgetTheme.light),
    ]) {
      await change();
      await pumpEventQueue();
    }

    expect(r.gateway.appearances.map((a) => a['appTheme']), [
      'system',
      'dark',
      'dark',
      'dark',
    ]);
    expect(r.gateway.appearances.last, {
      'appTheme': 'dark',
      'todayTheme': 'light',
      'todayMetrics': ['steps', 'heartRate'],
      'units': 'metric',
    });
    expect(r.configs.saved?.metrics, [
      WidgetMetric.steps,
      WidgetMetric.heartRate,
    ]);
    expect(r.gateway.snapshots, hasLength(1));
  });

  test('a saved workout publishes the last workout again', () async {
    final r = rig();
    startWidgetPush(r.container);
    await settle(r.container);
    expect(r.gateway.snapshots.single['lastWorkout'], isNull);

    r.workouts.items = [
      WorkoutListItem(
        id: 1,
        type: WorkoutType.cycling,
        start: metricsNow.subtract(const Duration(hours: 2)),
        end: metricsNow.subtract(const Duration(hours: 1)),
        utcOffset: Duration.zero,
        elapsed: const Duration(minutes: 55),
        distanceMeters: 18400,
      ),
    ];
    r.container.read(dataRevisionProvider.notifier).bump();
    await settle(r.container);

    expect(r.gateway.snapshots, hasLength(2));
    expect(r.gateway.snapshots.last['lastWorkout'], {
      'type': 'cycling',
      'startMs': metricsNow
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch,
      'elapsedSeconds': 3300,
      'distanceMeters': 18400.0,
    });
  });

  test('the unit system goes to the widgets with the appearance', () async {
    final r = rig(units: UnitSystem.imperial);
    startWidgetPush(r.container);
    await settle(r.container);
    await r.container.read(unitSystemProvider.future);
    await pumpEventQueue();

    expect(r.gateway.appearances.last['units'], 'imperial');

    await r.container
        .read(unitSystemProvider.notifier)
        .select(UnitSystem.metric);
    await pumpEventQueue();

    expect(r.gateway.appearances.last['units'], 'metric');
  });

  test(
    'turning a module off removes its field permanently and republishes',
    () async {
      final r = rig(
        modules: {ModuleId.openScore, ModuleId.body},
        config: TodayWidgetConfig(
          metrics: const [
            WidgetMetric.dayScore,
            WidgetMetric.steps,
            WidgetMetric.weight,
          ],
        ),
      );
      startWidgetPush(r.container);
      await r.container.read(enabledModulesProvider.future);
      await settle(r.container);

      expect(r.gateway.appearances.last['todayMetrics'], [
        'dayScore',
        'steps',
        'weight',
      ]);

      await r.container
          .read(enabledModulesProvider.notifier)
          .disable(ModuleId.openScore);
      await pumpEventQueue();

      expect(r.configs.saved?.metrics, [
        WidgetMetric.steps,
        WidgetMetric.weight,
      ]);
      expect(r.gateway.appearances.last['todayMetrics'], ['steps', 'weight']);

      // Re-enabling the module must not bring the removed field back.
      await r.container
          .read(enabledModulesProvider.notifier)
          .enable(ModuleId.openScore);
      await pumpEventQueue();

      expect(r.configs.saved?.metrics, [
        WidgetMetric.steps,
        WidgetMetric.weight,
      ]);
      expect(r.gateway.appearances.last['todayMetrics'], ['steps', 'weight']);
    },
  );

  test(
    'hiding numbers drops energy from appearance without deleting it and restores it on unhide',
    () async {
      final r = rig(
        modules: {ModuleId.body, ModuleId.energy},
        profile: fullProfile,
        config: TodayWidgetConfig(
          metrics: const [
            WidgetMetric.weight,
            WidgetMetric.energy,
            WidgetMetric.steps,
          ],
        ),
      );
      startWidgetPush(r.container);
      await r.container.read(enabledModulesProvider.future);
      await r.container.read(hideNumbersProvider.future);
      await r.container.read(userProfileProvider.future);
      await settle(r.container);

      expect(r.gateway.appearances.last['todayMetrics'], [
        'weight',
        'energy',
        'steps',
      ]);

      await r.container.read(hideNumbersProvider.notifier).set(hidden: true);
      await pumpEventQueue();

      expect(r.gateway.appearances.last['todayMetrics'], ['weight', 'steps']);
      expect(
        r.container.read(todayWidgetConfigProvider).metrics,
        [WidgetMetric.weight, WidgetMetric.energy, WidgetMetric.steps],
      );

      await r.container.read(hideNumbersProvider.notifier).set(hidden: false);
      await pumpEventQueue();

      expect(r.gateway.appearances.last['todayMetrics'], [
        'weight',
        'energy',
        'steps',
      ]);
    },
  );

  test('underage profile omits energy from published appearance', () async {
    final r = rig(
      modules: {ModuleId.energy},
      profile: const UserProfile(birthYear: 2012),
      config: TodayWidgetConfig(
        metrics: const [WidgetMetric.energy, WidgetMetric.steps],
      ),
    );
    startWidgetPush(r.container);
    await r.container.read(enabledModulesProvider.future);
    await r.container.read(hideNumbersProvider.future);
    await r.container.read(userProfileProvider.future);
    await settle(r.container);

    expect(r.gateway.appearances.last['todayMetrics'], ['steps']);
  });
}
