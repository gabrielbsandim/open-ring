import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/in_memory_projection_store.dart';
import 'package:open_ring/features/trajectory/domain/projection_store.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_projection.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/projections_screen.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_formula_screen.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_screen.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_states.dart';

import '../../../helpers/layout_harness.dart';
import 'trajectory_screen_fixtures.dart';

const _inside = LocalDate(2026, 10, 5);
const _above = LocalDate(2026, 10, 12);
const _waiting = LocalDate(2026, 10, 19);
const _below = LocalDate(2026, 9, 14);
const _unchecked = LocalDate(2026, 8, 3);

TrajectoryProjection _row(LocalDate monday, double low, double high) =>
    TrajectoryProjection(
      monday: monday,
      trendKg: 78,
      rateKgPerWeek: -0.3,
      lowKg: low,
      midKg: (low + high) / 2,
      highKg: high,
      createdAt: DateTime.utc(2026),
    );

Future<ProjectionStore> _seeded({bool unchecked = false}) async {
  final store = InMemoryProjectionStore();
  await store.insertIfAbsent(_row(_below, 85, 90));
  await store.insertIfAbsent(_row(_inside, 70, 85));
  await store.insertIfAbsent(_row(_above, 60, 65));
  await store.insertIfAbsent(_row(_waiting, 70, 85));
  if (unchecked) await store.insertIfAbsent(_row(_unchecked, 70, 85));
  return store;
}

final class _FailingStore implements ProjectionStore {
  @override
  Future<List<TrajectoryProjection>> all() => Future.error(StateError('db'));

  @override
  Future<bool> insertIfAbsent(TrajectoryProjection projection) async => false;

  @override
  Future<int> deleteAll() async => 0;
}

List<Override> _overrides(
  ProjectionStore store, {
  bool hidden = false,
  UnitSystem units = UnitSystem.metric,
  TrajectoryView? view,
}) => [
  ...trajectoryOverrides(
    view: view ?? readyView(),
    hidden: hidden,
    units: units,
  ),
  projectionStoreProvider.overrideWithValue(store),
];

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  ProjectionStore store, {
  bool hidden = false,
  UnitSystem units = UnitSystem.metric,
  TrajectoryView? view,
  double scale = 1,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
}) => pumpScaled(
  tester,
  screenHost(screen),
  textScaler: TextScaler.linear(scale),
  brightness: brightness,
  locale: locale,
  size: const Size(360, 4000),
  overrides: _overrides(store, hidden: hidden, units: units, view: view),
);

const _projectionsStub = 'projections stub';
const _formulaStub = 'formula stub';

Future<void> _pumpRouted(WidgetTester tester, ProjectionStore store) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const TrajectoryScreen()),
      GoRoute(
        path: AppPaths.trajectoryProjections,
        builder: (_, _) => const Scaffold(body: Text(_projectionsStub)),
      ),
      GoRoute(
        path: AppPaths.trajectoryFormula,
        builder: (_, _) => const Scaffold(body: Text(_formulaStub)),
      ),
    ],
  );
  return pumpScaled(
    tester,
    routerHost(router),
    textScaler: TextScaler.noScaling,
    brightness: Brightness.light,
    locale: const Locale('en'),
    size: const Size(360, 4000),
    overrides: _overrides(store),
  );
}

void main() {
  group('summary card on the Trajectory screen', () {
    testWidgets('counts checked rows by grade and the waiting ones', (
      tester,
    ) async {
      await _pump(tester, const TrajectoryScreen(), await _seeded());

      expect(find.byKey(ProjectionsKeys.card), findsOneWidget);
      expect(find.text('3 checked'), findsOneWidget);
      expect(
        find.text('1 inside the band · 1 below the band · 1 above the band'),
        findsOneWidget,
      );
      expect(find.text('1 waiting for its check day.'), findsOneWidget);
    });

    testWidgets('says none yet with an empty store', (tester) async {
      await _pump(tester, const TrajectoryScreen(), InMemoryProjectionStore());

      expect(find.byKey(ProjectionsKeys.empty), findsOneWidget);
      expect(find.byKey(ProjectionsKeys.card), findsNothing);
    });

    for (final (name, view) in [
      ('guard', guardView as TrajectoryView),
      ('building', const TrajectoryBuilding(null)),
    ]) {
      testWidgets('shows on $name too', (tester) async {
        await _pump(
          tester,
          const TrajectoryScreen(),
          await _seeded(),
          view: view,
        );

        expect(find.byKey(ProjectionsKeys.card), findsOneWidget);
      });
    }

    testWidgets('is absent when refused', (tester) async {
      await _pump(
        tester,
        const TrajectoryScreen(),
        await _seeded(),
        view: const TrajectoryRefused(TrajectoryRefusal.pregnancy),
      );

      expect(find.byKey(ProjectionsKeys.card), findsNothing);
      expect(find.byKey(TrajectoryKeys.formulaLink), findsOneWidget);
    });

    testWidgets('tapping it opens the list', (tester) async {
      await _pumpRouted(tester, await _seeded());

      await tester.ensureVisible(find.byKey(ProjectionsKeys.card));
      await tester.tap(find.byKey(ProjectionsKeys.card));
      await tester.pumpAndSettle();

      expect(find.text(_projectionsStub), findsOneWidget);
    });

    testWidgets('the formula link opens How we calculate', (tester) async {
      await _pumpRouted(tester, await _seeded());

      await tester.ensureVisible(find.byKey(TrajectoryKeys.formulaLink));
      await tester.tap(find.byKey(TrajectoryKeys.formulaLink));
      await tester.pumpAndSettle();

      expect(find.text(_formulaStub), findsOneWidget);
    });
  });

  group('projections screen', () {
    testWidgets('lists rows newest first with range, trend and tag', (
      tester,
    ) async {
      await _pump(tester, const ProjectionsScreen(), await _seeded());

      final order = [_waiting, _above, _inside, _below]
          .map((m) => tester.getTopLeft(find.byKey(ProjectionsKeys.row(m))).dy)
          .toList();
      expect(order, [...order]..sort());
      expect(find.text('For Nov 16: 70.0 to 85.0 kg.'), findsOneWidget);
      expect(find.text('checks Nov 16'), findsOneWidget);
      expect(
        find.textContaining('For Nov 2: 70.0 to 85.0 kg. Trend'),
        findsOneWidget,
      );
      expect(find.text('inside'), findsOneWidget);
      expect(find.text('below'), findsOneWidget);
      expect(find.text('above'), findsOneWidget);
      expect(
        find.text('Outside the band is not your mistake.'),
        findsOneWidget,
      );
    });

    testWidgets('a past row with no weigh-in by then is not checked', (
      tester,
    ) async {
      await _pump(
        tester,
        const ProjectionsScreen(),
        await _seeded(unchecked: true),
      );

      expect(find.text('not checked'), findsOneWidget);
      expect(
        find.text(
          'No weigh-in left up to that day, so it could not be checked.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('all inside reads the inside note', (tester) async {
      final store = InMemoryProjectionStore();
      await store.insertIfAbsent(_row(_inside, 70, 85));
      await _pump(tester, const ProjectionsScreen(), store);

      expect(find.text('All inside the band so far.'), findsOneWidget);
    });

    testWidgets('only waiting rows show no note', (tester) async {
      final store = InMemoryProjectionStore();
      await store.insertIfAbsent(_row(_waiting, 70, 85));
      await _pump(tester, const ProjectionsScreen(), store);

      expect(find.byKey(ProjectionsKeys.note), findsNothing);
    });

    testWidgets('hidden numbers keep dates and verdicts, no weight', (
      tester,
    ) async {
      await _pump(
        tester,
        const ProjectionsScreen(),
        await _seeded(),
        hidden: true,
      );

      expect(find.text('For Nov 16.'), findsOneWidget);
      expect(find.text('inside'), findsOneWidget);
      expect(find.textContaining('kg'), findsNothing);
      expect(find.textContaining(RegExp(r'\d\.\d')), findsNothing);
    });

    testWidgets('pounds show the range in lb', (tester) async {
      await _pump(
        tester,
        const ProjectionsScreen(),
        await _seeded(),
        units: UnitSystem.imperial,
      );

      expect(find.textContaining('lb.'), findsWidgets);
      expect(find.textContaining('kg'), findsNothing);
    });

    testWidgets('an empty store says none yet', (tester) async {
      await _pump(tester, const ProjectionsScreen(), InMemoryProjectionStore());

      expect(find.textContaining('None yet.'), findsOneWidget);
    });

    testWidgets('a read error shows the retry card', (tester) async {
      await _pump(tester, const ProjectionsScreen(), _FailingStore());

      expect(find.byType(TrajectoryErrorCard), findsOneWidget);
      expect(find.byKey(ProjectionsKeys.row(_inside)), findsNothing);
    });
  });

  group('layout', () {
    for (final scale in [1.0, 1.3, 2.0]) {
      for (final locale in const [Locale('en'), Locale('de')]) {
        for (final brightness in Brightness.values) {
          final name = '$scale ${locale.languageCode} ${brightness.name}';
          testWidgets('projections screen fits at $name', (tester) async {
            await _pump(
              tester,
              const ProjectionsScreen(),
              await _seeded(unchecked: true),
              scale: scale,
              locale: locale,
              brightness: brightness,
            );

            expect(find.byKey(ProjectionsKeys.row(_inside)), findsOneWidget);
          });

          testWidgets('formula screen fits at $name', (tester) async {
            await _pump(
              tester,
              const TrajectoryFormulaScreen(),
              InMemoryProjectionStore(),
              scale: scale,
              locale: locale,
              brightness: brightness,
            );

            expect(
              find.byKey(TrajectoryFormulaKeys.protections),
              findsOneWidget,
            );
            await tester.scrollUntilVisible(
              find.byKey(TrajectoryFormulaKeys.cannot),
              300,
            );
            expect(find.byKey(TrajectoryFormulaKeys.cannot), findsOneWidget);
          });
        }
      }
    }
  });

  testWidgets('formula screen names the guard, floor and age', (tester) async {
    await _pump(
      tester,
      const TrajectoryFormulaScreen(),
      InMemoryProjectionStore(),
    );

    expect(
      find.text(
        'Loss above 1% of body weight a week: the scenario is not drawn.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('BMI 18.5 floor'), findsOneWidget);
    expect(find.text('Adults only, from 18.'), findsOneWidget);
  });
}
