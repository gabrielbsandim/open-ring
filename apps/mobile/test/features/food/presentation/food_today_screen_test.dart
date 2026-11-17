import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/presentation/effort_week_tile.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/presentation/food_row.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/today/presentation/today_cards.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';

import '../../../helpers/fake_health_reader.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/metrics_pump.dart';
import '../food_fakes.dart';

const _neverSyncedScenario = MetricsScenario(
  nights: 0,
  activityDays: 0,
  ring: RingStatus(paired: true, name: 'R09_C0FE', model: 'R09'),
);

Future<void> _pumpToday(
  WidgetTester tester,
  MetricsScenario scenario, {
  required Set<ModuleId> modules,
  List<Override> extra = const [],
  Size size = phoneSize,
}) => pumpScaled(
  tester,
  screenHost(const TodayScreen()),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  size: size,
  overrides: [
    ...metricsOverrides(scenario),
    ...extra,
    moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
  ],
);

List<Override> _foodOn() => foodStoreOverrides(
  meals: TestMealStore(),
  camera: FakeMealCamera(),
  clock: () => metricsNow,
);

Future<List<Override>> _importedSleep() async {
  final store = InMemoryHealthReadStore();
  await store.setEnabled(HealthRecordKind.sleep, enabled: true);
  return [
    healthReadStoreProvider.overrideWithValue(store),
    healthReaderProvider.overrideWithValue(
      FakeHealthReader(access: HealthAccess.granted),
    ),
  ];
}

void main() {
  group('criterion 1: Food off on Today', () {
    testWidgets('the existing Today setup with no meal overrides shows no row '
        'and throws nothing', (tester) async {
      await pumpMetrics(
        tester,
        screenHost(const TodayScreen()),
        fullDataScenario,
      );

      expect(find.byKey(FoodRowKeys.row, skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a throwing meal store is never built', (tester) async {
      final reads = StoreReads();

      await _pumpToday(
        tester,
        fullDataScenario,
        modules: const {ModuleId.effort},
        extra: [
          ...reads.overrides(),
          effortWeekProvider.overrideWith(
            (ref) async => const EffortWeek(
              monday: LocalDate(2026, 11, 9),
              points: 42,
              strengthDays: 0,
            ),
          ),
        ],
      );

      expect(find.byKey(FoodRowKeys.row, skipOffstage: false), findsNothing);
      expect(reads.any, isFalse, reason: 'Today must not read the stores');
      expect(tester.takeException(), isNull);
    });
  });

  group('D3: the row on Today while Food is on', () {
    final scenarios = {
      'without a ring': noDataScenario,
      'before the first sync': _neverSyncedScenario,
      'with full data': fullDataScenario,
      'offline': offlineScenario,
    };
    for (final MapEntry(key: name, value: scenario) in scenarios.entries) {
      testWidgets('shows $name', (tester) async {
        await _pumpToday(
          tester,
          scenario,
          modules: const {ModuleId.food},
          extra: _foodOn(),
        );

        expect(
          find.byKey(FoodRowKeys.row, skipOffstage: false),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shows without a ring and with an imported night', (
      tester,
    ) async {
      await _pumpToday(
        tester,
        const MetricsScenario(
          nights: 1,
          activityDays: 0,
          ring: RingStatus.unpaired,
        ),
        modules: const {ModuleId.food},
        extra: [..._foodOn(), ...await _importedSleep()],
      );

      expect(find.byKey(TodayKeys.sleep), findsOneWidget);
      expect(find.byKey(FoodRowKeys.row, skipOffstage: false), findsOneWidget);
    });

    testWidgets('sits right after the Effort tile and above readiness', (
      tester,
    ) async {
      await _pumpToday(
        tester,
        fullDataScenario,
        modules: const {ModuleId.food, ModuleId.effort},
        size: const Size(360, 4000),
        extra: [
          ..._foodOn(),
          effortWeekProvider.overrideWith(
            (ref) async => const EffortWeek(
              monday: LocalDate(2026, 11, 9),
              points: 42,
              strengthDays: 0,
            ),
          ),
        ],
      );

      final effort = tester.getTopLeft(find.byKey(EffortWeekTileKeys.tile));
      final row = tester.getTopLeft(find.byKey(FoodRowKeys.row));
      final readiness = tester.getTopLeft(find.byKey(TodayKeys.readiness));

      expect(row.dy, greaterThan(effort.dy));
      expect(row.dy, lessThan(readiness.dy));
    });
  });
}
