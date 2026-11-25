import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/domain/weigh_in_store.dart';
import 'package:open_ring/features/body/presentation/body_screen.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/in_memory_projection_store.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_entry_row.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../trajectory/presentation/trajectory_screen_fixtures.dart';

const _en = Locale('en');
const _tall = Size(360, 2600);
const Set<ModuleId> _on = {ModuleId.body, ModuleId.trajectory};
const _adult = UserProfile(birthYear: 1990, heightCentimeters: 175);

UnitFormat _units() => UnitFormat(
  MetricFormat(lookupAppLocalizations(_en), _en.toString()),
  UnitSystem.metric,
);

class _Reads {
  int views = 0;
}

Future<InMemoryWeighInStore> _series({int days = 36}) async {
  final store = InMemoryWeighInStore();
  for (var age = days - 1; age >= 0; age--) {
    await store.add(
      WeighInDraft(
        at: metricsNow.subtract(Duration(days: age, hours: 1)),
        offsetMinutes: 0,
        kilograms: 80 - (days - 1 - age) * 0.05 + (age.isEven ? 0.3 : -0.3),
      ),
    );
  }
  return store;
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  required WeighInStore store,
  Set<ModuleId> modules = _on,
  _Reads? reads,
  TrajectoryView? view,
  bool real = false,
  InMemoryProjectionStore? projections,
  bool hidden = false,
  double scale = 1,
  Brightness brightness = Brightness.light,
  Locale locale = _en,
}) async {
  final router = stubRouter(const BodyScreen());
  await pumpScaled(
    tester,
    routerHost(router),
    textScaler: TextScaler.linear(scale),
    brightness: brightness,
    locale: locale,
    size: _tall,
    overrides: <Override>[
      ...metricsOverrides(fullDataScenario),
      moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
      weighInStoreProvider.overrideWithValue(store),
      hideNumbersStoreProvider.overrideWithValue(
        InMemoryHideNumbersStore(hidden: hidden),
      ),
      userProfileStoreProvider.overrideWithValue(
        InMemoryUserProfileStore(_adult),
      ),
      goalStoreProvider.overrideWithValue(InMemoryGoalStore()),
      projectionStoreProvider.overrideWithValue(
        projections ?? InMemoryProjectionStore(),
      ),
      if (!real)
        trajectoryViewProvider.overrideWith((ref) {
          reads?.views++;
          return Future.value(view ?? readyView());
        }),
    ],
  );
  return router;
}

void main() {
  testWidgets('acceptance 7: with weigh-ins the row sits below the trend card '
      'and reads the 12 week range', (tester) async {
    final view = readyView();
    final units = _units();
    await _pump(tester, store: await _series(), view: view);

    final row = find.byKey(TrajectoryEntryRow.rowKey);
    expect(row, findsOneWidget);
    expect(
      tester.getTopLeft(row).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.byKey(BodyKeys.chart)).dy),
    );
    final text = tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .map((text) => text.data ?? '')
        .join('|');
    expect(text, contains(units.bodyWeightNumber(view.band.low)));
    expect(text, contains(units.bodyWeightNumber(view.band.high)));
  });

  testWidgets('acceptance 7: the row is the Trajectory entry with its title', (
    tester,
  ) async {
    await _pump(tester, store: await _series());

    expect(
      find.descendant(
        of: find.byKey(TrajectoryEntryRow.rowKey),
        matching: find.text(lookupAppLocalizations(_en).trajectoryTitle),
      ),
      findsOneWidget,
    );
  });

  testWidgets('acceptance 7: hidden numbers give a generic subtitle', (
    tester,
  ) async {
    final view = readyView();
    final units = _units();
    await _pump(tester, store: await _series(), view: view, hidden: true);

    expect(find.byKey(TrajectoryEntryRow.rowKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(TrajectoryEntryRow.rowKey),
        matching: find.textContaining(units.bodyWeightNumber(view.band.low)),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(TrajectoryEntryRow.rowKey),
        matching: find.textContaining('kg'),
      ),
      findsNothing,
    );
  });

  testWidgets('acceptance 7: a tap pushes the trajectory screen', (
    tester,
  ) async {
    final router = await _pump(tester, store: await _series());

    await tester.tap(find.byKey(TrajectoryEntryRow.rowKey));
    await tester.pumpAndSettle();

    expect(find.text(trajectoryStub), findsOneWidget);
    expect(router.canPop(), isTrue);
  });

  testWidgets('with no weigh-in there is no row and the view is not read', (
    tester,
  ) async {
    final reads = _Reads();
    await _pump(tester, store: InMemoryWeighInStore(), reads: reads);

    expect(find.byKey(TrajectoryEntryRow.rowKey), findsNothing);
    expect(reads.views, 0);
  });

  testWidgets('a single weigh-in already shows the row', (tester) async {
    await _pump(tester, store: await _series(days: 1));

    expect(find.byKey(TrajectoryEntryRow.rowKey), findsOneWidget);
  });

  testWidgets('acceptance 8: module off shows no row and never reads the '
      'view', (tester) async {
    final reads = _Reads();
    await _pump(
      tester,
      store: await _series(),
      modules: const {ModuleId.body},
      reads: reads,
    );

    expect(find.byType(BodyScreen), findsOneWidget);
    expect(find.byKey(BodyKeys.chart), findsOneWidget);
    expect(find.byKey(TrajectoryEntryRow.rowKey), findsNothing);
    expect(reads.views, 0);
  });

  testWidgets('opening Body with the module on stores this Monday once', (
    tester,
  ) async {
    final projections = InMemoryProjectionStore();
    await _pump(
      tester,
      store: await _series(),
      real: true,
      projections: projections,
    );

    expect(find.byKey(TrajectoryEntryRow.rowKey), findsOneWidget);
    expect(await projections.all(), hasLength(1));
  });

  testWidgets('opening Body with the module off stores nothing', (
    tester,
  ) async {
    final projections = InMemoryProjectionStore();
    await _pump(
      tester,
      store: await _series(),
      modules: const {ModuleId.body},
      real: true,
      projections: projections,
    );

    expect(find.byKey(TrajectoryEntryRow.rowKey), findsNothing);
    expect(await projections.all(), isEmpty);
  });

  group('acceptance 9: no overflow', () {
    for (final layout in layoutMatrix()) {
      testWidgets('Body with the row at $layout', (tester) async {
        await _pump(
          tester,
          store: await _series(),
          scale: layout.scale,
          brightness: layout.brightness,
          locale: layout.locale,
        );

        expect(find.byKey(TrajectoryEntryRow.rowKey), findsOneWidget);
      });

      testWidgets('Body with a generic row at $layout', (tester) async {
        await _pump(
          tester,
          store: await _series(),
          view: guardView,
          hidden: true,
          scale: layout.scale,
          brightness: layout.brightness,
          locale: layout.locale,
        );

        expect(find.byKey(TrajectoryEntryRow.rowKey), findsOneWidget);
      });
    }
  });
}
