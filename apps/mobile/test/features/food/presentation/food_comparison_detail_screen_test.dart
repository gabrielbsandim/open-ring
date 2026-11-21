import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/food/application/food_comparisons.dart';
import 'package:open_ring/features/food/application/food_nights.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_comparison_detail_screen.dart';
import 'package:open_ring/features/food/presentation/food_comparisons_screen.dart';
import 'package:open_ring/features/food/presentation/food_formula_screen.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../food_fakes.dart';

final _now = DateTime(2026, 11, 17, 21);

FoodComparisonsView _detailView() => FoodComparisonsView(
  firstNight: const LocalDate(2026, 8, 18),
  lastNight: const LocalDate(2026, 11, 15),
  updatedMonday: const LocalDate(2026, 11, 16),
  items: [
    FoodComparisonItem(
      link: FoodLink.alcoholThreeOrMore,
      leadOutcome: NightOutcome.heartRate,
      alsoOutcome: NightOutcome.hrv,
      alcoholLink: true,
      lead: const LinkPattern(pairs: 12, mean: 5.1, low: 1.6, high: 8.6),
      also: const LinkPattern(pairs: 12, mean: -19.5, low: -25.2, high: -13.4),
      leadPairs: const [
        FoodComparisonPair(
          exposedDay: LocalDate(2026, 9, 5),
          controlDay: LocalDate(2026, 9, 4),
          exposedHeartRate: 62,
          controlHeartRate: 56,
          diff: 6,
        ),
        FoodComparisonPair(
          exposedDay: LocalDate(2026, 11, 7),
          controlDay: LocalDate(2026, 11, 6),
          exposedHeartRate: 65,
          controlHeartRate: 58,
          diff: 7,
        ),
      ],
      leadSd: 2.8,
      leadT99: t99(11),
    ),
    FoodComparisonItem(
      link: FoodLink.lateLastMeal,
      leadOutcome: NightOutcome.heartRate,
      alsoOutcome: NightOutcome.hrv,
      alcoholLink: false,
      lead: const LinkPattern(pairs: 16, mean: 4.2, low: 1.6, high: 6.8),
      also: const LinkCollecting(pairs: 11, minimum: 14),
      leadPairs: const [
        FoodComparisonPair(
          exposedDay: LocalDate(2026, 11, 10),
          controlDay: LocalDate(2026, 11, 9),
          exposedHeartRate: 63,
          controlHeartRate: 59,
          diff: 4,
        ),
      ],
      leadSd: 2.1,
      leadT99: t99(15),
    ),
    FoodComparisonItem(
      link: FoodLink.caffeineAfter14,
      leadOutcome: NightOutcome.onset,
      alsoOutcome: NightOutcome.heartRate,
      alcoholLink: false,
      lead: const LinkNoClearDifference(
        pairs: 16,
        mean: -0.3,
        low: -13.6,
        high: 13.1,
      ),
      also: const LinkNoClearDifference(
        pairs: 16,
        mean: 0.4,
        low: -1.1,
        high: 1.9,
      ),
      leadPairs: [
        FoodComparisonPair(
          exposedDay: const LocalDate(2026, 11, 12),
          controlDay: const LocalDate(2026, 11, 11),
          exposedOnset: DateTime.utc(2026, 11, 12, 23, 35),
          controlOnset: DateTime.utc(2026, 11, 11, 23, 20),
          diff: 15,
        ),
      ],
      leadSd: 17.5,
      leadT99: t99(15),
    ),
    const FoodComparisonItem(
      link: FoodLink.heavyDinner,
      leadOutcome: NightOutcome.heartRate,
      alsoOutcome: NightOutcome.hrv,
      alcoholLink: false,
      lead: LinkCollecting(pairs: 9, minimum: 14),
      also: LinkCollecting(pairs: 9, minimum: 14),
      leadPairs: [],
    ),
    const FoodComparisonItem(
      link: FoodLink.alcoholOneToTwo,
      leadOutcome: NightOutcome.heartRate,
      alsoOutcome: NightOutcome.hrv,
      alcoholLink: true,
      lead: LinkCollecting(pairs: 7, minimum: 10),
      also: LinkCollecting(pairs: 7, minimum: 10),
      leadPairs: [],
    ),
  ],
  regularity: const MealRegularity(
    completeDays: 14,
    firstMealSdMinutes: 68,
    weekendLaterMinutes: 130,
  ),
);

List<Override> _routerOverrides({
  bool foodOn = true,
  FoodComparisonsView? view,
}) => [
  moduleStoreProvider.overrideWithValue(
    InMemoryModuleStore({if (foodOn) ModuleId.food}),
  ),
  clockProvider.overrideWithValue(() => _now),
  mealStoreProvider.overrideWithValue(TestMealStore()),
  photoStoreProvider.overrideWithValue(InMemoryPhotoStore()),
  mealCameraProvider.overrideWithValue(FakeMealCamera()),
  foodNightsProvider.overrideWith((ref) async => const []),
  goalStoreProvider.overrideWithValue(InMemoryGoalStore()),
  if (view != null) foodComparisonsProvider.overrideWith((ref) async => view),
];

void main() {
  group('FoodComparisonDetailScreen routing and gating', () {
    test('AppPaths.foodComparisonOf maps all 5 links', () {
      for (final link in FoodLink.values) {
        expect(
          AppPaths.foodComparisonOf(link),
          '/today/food/comparisons/${link.name}',
        );
      }
    });

    testWidgets('Food disabled renders empty page and reads zero stores', (
      tester,
    ) async {
      final reads = StoreReads();
      await pumpScaled(
        tester,
        screenHost(
          const FoodComparisonDetailScreen(link: FoodLink.alcoholThreeOrMore),
        ),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: [
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore()),
          clockProvider.overrideWithValue(() => _now),
          ...reads.overrides(),
        ],
      );

      expect(find.byKey(FoodComparisonDetailKeys.lead), findsNothing);
      expect(find.byKey(FoodComparisonDetailKeys.verdictCard), findsNothing);
      expect(reads.any, isFalse);
    });

    testWidgets('unknown :link route renders fallback not-found copy', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final container = await pumpOnboardingApp(
        tester,
        store: InMemoryOnboardingStore(completed: true),
        overrides: [
          ...bleOverrides(),
          ...ringOverrides(),
          ...onboardingOverrides(),
          ..._routerOverrides(view: _detailView()),
        ],
      );

      container.read(appRouterProvider).go('/today/food/comparisons/unknown');
      await tester.pumpAndSettle();

      expect(find.byKey(FoodComparisonDetailKeys.notFound), findsOneWidget);
      expect(find.text(l10n.foodCompDetailNotFound), findsOneWidget);
    });

    testWidgets(
      'tapping comparison card navigates to detail and formulaLink navigates '
      'to FoodFormulaScreen',
      (tester) async {
        final container = await pumpOnboardingApp(
          tester,
          at: AppPaths.foodComparisons,
          store: InMemoryOnboardingStore(completed: true),
          overrides: [
            ...bleOverrides(),
            ...ringOverrides(),
            ...onboardingOverrides(),
            ..._routerOverrides(view: _detailView()),
          ],
        );

        await tester.tap(
          find.byKey(FoodComparisonsKeys.card(FoodLink.alcoholThreeOrMore)),
        );
        await tester.pumpAndSettle();

        expect(
          container.read(appRouterProvider).state.uri.path,
          AppPaths.foodComparisonOf(FoodLink.alcoholThreeOrMore),
        );
        expect(find.byType(FoodComparisonDetailScreen), findsOneWidget);

        await tester.scrollUntilVisible(
          find.byKey(FoodComparisonDetailKeys.formulaLink),
          140,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(FoodComparisonDetailKeys.formulaLink));
        await tester.pumpAndSettle();
        expect(find.byType(FoodFormulaScreen), findsOneWidget);
      },
    );
  });

  group('FoodComparisonDetailScreen states and math', () {
    testWidgets(
      'renders LinkPattern verdict, Also pattern, newest-first HR pairs, exact '
      't99/SD math, alcohol-only rule note, and truthful limits',
      (tester) async {
        final l10n = lookupAppLocalizations(const Locale('en'));
        await pumpScaled(
          tester,
          screenHost(
            const FoodComparisonDetailScreen(link: FoodLink.alcoholThreeOrMore),
          ),
          textScaler: TextScaler.noScaling,
          brightness: Brightness.dark,
          locale: const Locale('en'),
          overrides: _routerOverrides(view: _detailView()),
          size: const Size(360, 2600),
        );

        expect(find.byKey(FoodComparisonDetailKeys.lead), findsOneWidget);
        expect(
          find.textContaining('Nights with drinking often end later.'),
          findsAtLeastNWidgets(2),
        );
        expect(
          find.textContaining(
            'Nightly HRV: 20% lower (13% to 25%), in 12 pairs.',
          ),
          findsOneWidget,
        );

        // Newest-first order: 2026-11-07 (index 0) before 2026-09-05 (index 1).
        final row0 = tester.getTopLeft(
          find.byKey(FoodComparisonDetailKeys.pairRow(0)),
        );
        final row1 = tester.getTopLeft(
          find.byKey(FoodComparisonDetailKeys.pairRow(1)),
        );
        expect(row0.dy, lessThan(row1.dy));
        expect(
          find.descendant(
            of: find.byKey(FoodComparisonDetailKeys.pairRow(0)),
            matching: find.textContaining('65 bpm'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(FoodComparisonDetailKeys.pairRow(0)),
            matching: find.text('+7'),
          ),
          findsOneWidget,
        );

        final expr = tester
            .widget<Text>(find.byKey(FoodComparisonDetailKeys.ruleExpression))
            .data!;
        expect(
          expr,
          allOf(
            contains('pairs: 12 (minimum 10)'),
            contains('t(99%, 11) = 3.106'),
            contains('2.8'),
            contains('2 bpm'),
          ),
        );
        expect(find.textContaining('Open Score is on.'), findsOneWidget);
        expect(
          find.textContaining('without alcohol on either night'),
          findsNothing,
        );
        expect(find.text(l10n.foodCompCannotTagged), findsOneWidget);
        expect(find.text(l10n.foodCompCannotRing), findsOneWidget);
      },
    );

    testWidgets('handles LinkCollecting for Also while lead is decided, and '
        'alcohol-free note for non-alcohol links', (tester) async {
      await pumpScaled(
        tester,
        screenHost(
          const FoodComparisonDetailScreen(link: FoodLink.lateLastMeal),
        ),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: _routerOverrides(view: _detailView()),
        size: const Size(360, 2600),
      );

      expect(
        find.textContaining('Nightly HRV: 11 of 14 comparable nights so far.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('without alcohol on either night'),
        findsOneWidget,
      );
    });

    testWidgets(
      'renders LinkNoClearDifference with onset clock pairs and signed '
      'secondary interval',
      (tester) async {
        await pumpScaled(
          tester,
          screenHost(
            const FoodComparisonDetailScreen(link: FoodLink.caffeineAfter14),
          ),
          textScaler: TextScaler.noScaling,
          brightness: Brightness.light,
          locale: const Locale('en'),
          overrides: _routerOverrides(view: _detailView()),
          size: const Size(360, 2600),
        );

        expect(find.textContaining('With 16 pairs'), findsOneWidget);
        expect(find.textContaining('15 min'), findsAtLeastNWidgets(2));
        expect(
          find.textContaining('No clear difference in your data so far'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Nightly heart rate: no clear difference'),
          findsOneWidget,
        );
        expect(find.textContaining('23:35'), findsOneWidget);
        expect(find.textContaining('23:20'), findsOneWidget);
        expect(find.textContaining('+15'), findsOneWidget);
      },
    );

    testWidgets(
      'renders LinkCollecting lead without Also, Pairs, or Rule cards',
      (tester) async {
        final l10n = lookupAppLocalizations(const Locale('en'));
        await pumpScaled(
          tester,
          screenHost(
            const FoodComparisonDetailScreen(link: FoodLink.heavyDinner),
          ),
          textScaler: TextScaler.noScaling,
          brightness: Brightness.dark,
          locale: const Locale('en'),
          overrides: _routerOverrides(view: _detailView()),
          size: const Size(360, 2200),
        );

        expect(
          find.textContaining('9 of 14 comparable nights'),
          findsOneWidget,
        );
        expect(find.text(l10n.foodCompCollectingWhy(14)), findsOneWidget);
        expect(find.byKey(FoodComparisonDetailKeys.alsoCard), findsNothing);
        expect(find.byKey(FoodComparisonDetailKeys.pairsCard), findsNothing);
        expect(find.byKey(FoodComparisonDetailKeys.ruleCard), findsNothing);
        expect(find.byKey(FoodComparisonDetailKeys.cannotCard), findsOneWidget);
      },
    );

    testWidgets('shows metricLoadError when provider fails', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await pumpScaled(
        tester,
        screenHost(
          const FoodComparisonDetailScreen(link: FoodLink.alcoholThreeOrMore),
        ),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: [
          moduleStoreProvider.overrideWithValue(
            InMemoryModuleStore({ModuleId.food}),
          ),
          clockProvider.overrideWithValue(() => _now),
          foodComparisonsProvider.overrideWith(
            (ref) => Future<FoodComparisonsView>.error(StateError('fail')),
          ),
        ],
      );

      expect(find.text(l10n.metricLoadError), findsOneWidget);
    });
  });
}
