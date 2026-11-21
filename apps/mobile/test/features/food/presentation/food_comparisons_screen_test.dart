import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/food/application/food_comparisons.dart';
import 'package:open_ring/features/food/application/food_nights.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_comparisons_screen.dart';
import 'package:open_ring/features/food/presentation/food_day_screen.dart';
import 'package:open_ring/features/food/presentation/food_formula_screen.dart';
import 'package:open_ring/features/food/presentation/food_week_screen.dart';
import 'package:open_ring/features/goals/application/goal_intake_providers.dart';
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

FoodComparisonsView _sampleView({
  double meanHr = 5.1,
  double lowHr = 1.6,
  double highHr = 8.6,
  double? weekendShift = 130.0,
  bool regularDone = true,
}) => FoodComparisonsView(
  firstNight: const LocalDate(2026, 8, 18),
  lastNight: const LocalDate(2026, 11, 15),
  updatedMonday: const LocalDate(2026, 11, 16),
  items: [
    FoodComparisonItem(
      link: FoodLink.alcoholThreeOrMore,
      leadOutcome: NightOutcome.heartRate,
      alsoOutcome: NightOutcome.hrv,
      alcoholLink: true,
      lead: LinkPattern(pairs: 12, mean: meanHr, low: lowHr, high: highHr),
      also: const LinkPattern(pairs: 12, mean: -19.5, low: -25.2, high: -13.4),
      leadPairs: const [],
      leadSd: 2.8,
      leadT99: 3.106,
    ),
    const FoodComparisonItem(
      link: FoodLink.lateLastMeal,
      leadOutcome: NightOutcome.heartRate,
      alsoOutcome: NightOutcome.hrv,
      alcoholLink: false,
      lead: LinkPattern(pairs: 16, mean: 4.2, low: 1.6, high: 6.8),
      also: LinkNoClearDifference(pairs: 16, mean: -6, low: -12, high: 0.4),
      leadPairs: [],
    ),
    const FoodComparisonItem(
      link: FoodLink.caffeineAfter14,
      leadOutcome: NightOutcome.onset,
      alsoOutcome: NightOutcome.heartRate,
      alcoholLink: false,
      lead: LinkNoClearDifference(
        pairs: 16,
        mean: -0.3,
        low: -13.6,
        high: 13.1,
      ),
      also: LinkNoClearDifference(pairs: 16, mean: 0.4, low: -1.1, high: 1.9),
      leadPairs: [],
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
  regularity: regularDone
      ? MealRegularity(
          completeDays: 14,
          firstMealSdMinutes: 68,
          weekendLaterMinutes: weekendShift,
        )
      : const RegularityCollecting(completeDays: 6, minimum: 10),
);

List<Override> _routerOverrides({
  bool foodOn = true,
  bool softMode = false,
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
  softModeProvider.overrideWith((ref) async => softMode),
  if (view != null) foodComparisonsProvider.overrideWith((ref) async => view),
];

void main() {
  group('FoodComparisonsScreen routing and gating', () {
    test('AppPaths.foodComparisons is /today/food/comparisons', () {
      expect(AppPaths.foodComparisons, '/today/food/comparisons');
    });

    testWidgets('Food disabled renders empty page and reads zero stores', (
      tester,
    ) async {
      final reads = StoreReads();
      await pumpScaled(
        tester,
        screenHost(const FoodComparisonsScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: [
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore()),
          clockProvider.overrideWithValue(() => _now),
          ...reads.overrides(),
        ],
      );

      expect(find.byKey(FoodWeekKeys.tabs), findsNothing);
      expect(find.byKey(FoodComparisonsKeys.lead), findsNothing);
      expect(reads.any, isFalse);
    });

    testWidgets(
      'FoodSectionTabs switches between Day, Week, and Comparisons and taps '
      'formulaLink into FoodFormulaScreen',
      (tester) async {
        final container = await pumpOnboardingApp(
          tester,
          at: AppPaths.food,
          store: InMemoryOnboardingStore(completed: true),
          overrides: [
            ...bleOverrides(),
            ...ringOverrides(),
            ...onboardingOverrides(),
            ..._routerOverrides(view: _sampleView()),
          ],
        );

        expect(find.byType(FoodDayScreen), findsOneWidget);
        await tester.tap(find.byKey(FoodWeekKeys.tabWeek));
        await tester.pumpAndSettle();
        expect(
          container.read(appRouterProvider).state.uri.path,
          AppPaths.foodWeek,
        );
        expect(find.byType(FoodWeekScreen), findsOneWidget);

        await tester.tap(find.byKey(FoodWeekKeys.tabComparisons));
        await tester.pumpAndSettle();

        expect(
          container.read(appRouterProvider).state.uri.path,
          AppPaths.foodComparisons,
        );
        expect(find.byType(FoodComparisonsScreen), findsOneWidget);
        expect(
          tester
              .widget<SegmentedButton<FoodSection>>(
                find.byKey(FoodWeekKeys.tabs),
              )
              .selected,
          {FoodSection.comparisons},
        );

        // Tapping Comparisons while active stays put.
        await tester.tap(find.byKey(FoodWeekKeys.tabComparisons));
        await tester.pumpAndSettle();
        expect(
          container.read(appRouterProvider).state.uri.path,
          AppPaths.foodComparisons,
        );

        await tester.scrollUntilVisible(
          find.byKey(FoodComparisonsKeys.formulaLink),
          140,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(FoodComparisonsKeys.formulaLink));
        await tester.pumpAndSettle();
        expect(find.byType(FoodFormulaScreen), findsOneWidget);
      },
    );

    testWidgets('stays visible when Goals soft mode is on', (tester) async {
      await pumpScaled(
        tester,
        screenHost(const FoodComparisonsScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: _routerOverrides(softMode: true, view: _sampleView()),
        size: const Size(360, 2200),
      );

      expect(find.byKey(FoodComparisonsKeys.lead), findsOneWidget);
      expect(
        find.byKey(FoodComparisonsKeys.card(FoodLink.alcoholThreeOrMore)),
        findsOneWidget,
      );
      expect(find.byKey(FoodComparisonsKeys.regularityCard), findsOneWidget);
    });
  });

  group('FoodComparisonsScreen states and formatting', () {
    testWidgets(
      'renders Pattern, NoClearDifference, Collecting progress bars, and '
      'Regularity with weekend shift in neutral styling',
      (tester) async {
        final l10n = lookupAppLocalizations(const Locale('en'));
        await pumpScaled(
          tester,
          screenHost(const FoodComparisonsScreen()),
          textScaler: TextScaler.noScaling,
          brightness: Brightness.dark,
          locale: const Locale('en'),
          overrides: _routerOverrides(view: _sampleView()),
          size: const Size(360, 2200),
        );

        expect(find.textContaining('Caffeine after 14:00'), findsOneWidget);
        expect(find.textContaining('5 bpm higher'), findsOneWidget);
        expect(find.textContaining('2 bpm to 9 bpm'), findsOneWidget);
        expect(find.textContaining('16 pairs'), findsOneWidget);
        expect(
          find.textContaining('9 of 14 comparable nights'),
          findsOneWidget,
        );
        expect(
          find.byKey(FoodComparisonsKeys.progress(FoodLink.heavyDinner)),
          findsOneWidget,
        );
        expect(
          find.byKey(FoodComparisonsKeys.progress(FoodLink.alcoholThreeOrMore)),
          findsNothing,
        );

        expect(find.textContaining('1 h 8 min'), findsOneWidget);
        expect(find.textContaining('2 h 10 min later'), findsOneWidget);
        expect(find.text(l10n.foodRegNote), findsOneWidget);
        expect(find.text(l10n.foodCompFoot), findsOneWidget);

        // Zero status colors on neutral comparison cards.
        const c = AppColors.dark;
        for (final pill in tester.widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(
              FoodComparisonsKeys.tag(FoodLink.alcoholThreeOrMore),
            ),
            matching: find.byType(DecoratedBox),
          ),
        )) {
          final dec = pill.decoration as BoxDecoration;
          expect(dec.color, c.surfaceInner);
        }
        // Check all AccentTitle widgets use activity accent.
        for (final title in tester.widgetList<AccentTitle>(
          find.byType(AccentTitle),
        )) {
          expect(title.accent, c.activity);
        }
      },
    );

    testWidgets(
      'orders negative HRV magnitude range small-to-large and preserves < 1 '
      'decimals without rounding to 0',
      (tester) async {
        await pumpScaled(
          tester,
          screenHost(const FoodComparisonsScreen()),
          textScaler: TextScaler.noScaling,
          brightness: Brightness.light,
          locale: const Locale('en'),
          overrides: _routerOverrides(view: _sampleView(lowHr: 0.4)),
          size: const Size(360, 2200),
        );

        final ctx = tester.element(find.byType(FoodComparisonsScreen));
        final f = MetricFormat.of(ctx);
        expect(
          foodPatternRangeText(f, NightOutcome.hrv, -25.2, -13.4),
          '13% to 25%',
        );
        expect(
          foodPatternRangeText(f, NightOutcome.onset, 0.4, 30),
          '0.4 min to 30 min',
        );
        expect(find.textContaining('0.4 bpm to 9 bpm'), findsOneWidget);
      },
    );

    testWidgets('handles RegularityCollecting', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await pumpScaled(
        tester,
        screenHost(const FoodComparisonsScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: _routerOverrides(view: _sampleView(regularDone: false)),
        size: const Size(360, 2200),
      );
      expect(find.textContaining('6 of 10 complete days'), findsOneWidget);
      expect(find.text(l10n.foodRegNote), findsNothing);
    });

    testWidgets('handles earlier weekend regularity shift', (tester) async {
      await pumpScaled(
        tester,
        screenHost(const FoodComparisonsScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: _routerOverrides(view: _sampleView(weekendShift: -45)),
        size: const Size(360, 2200),
      );
      expect(find.textContaining('45 min earlier'), findsOneWidget);
    });

    testWidgets('handles zero weekend regularity shift', (tester) async {
      await pumpScaled(
        tester,
        screenHost(const FoodComparisonsScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: _routerOverrides(view: _sampleView(weekendShift: 0)),
        size: const Size(360, 2200),
      );
      expect(find.textContaining('On weekends it came'), findsNothing);
    });

    testWidgets('handles null weekend regularity shift', (tester) async {
      await pumpScaled(
        tester,
        screenHost(const FoodComparisonsScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: _routerOverrides(view: _sampleView(weekendShift: null)),
        size: const Size(360, 2200),
      );
      expect(find.textContaining('On weekends it came'), findsNothing);
    });

    testWidgets('shows metricLoadError when provider fails', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await pumpScaled(
        tester,
        screenHost(const FoodComparisonsScreen()),
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
