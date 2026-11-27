import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/food/application/food_nights.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_plate_screen.dart';
import 'package:open_ring/features/food/presentation/food_week_screen.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
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
const _w1Monday = LocalDate(2026, 11, 9);
const _w2Monday = LocalDate(2026, 11, 2);
const _w3Monday = LocalDate(2026, 10, 26);
const _w4Monday = LocalDate(2026, 10, 19);

final class _ThrowingMealStore implements MealStore {
  const new();

  @override
  Future<List<Meal>> between(LocalDate from, LocalDate to) =>
      Future.error(StateError('meal read error'));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected: ${invocation.memberName}');
}

void _seedPrototypeWeek(TestMealStore meals, LocalDate monday) {
  // 6 complete days, 18 mains: P=15, V=13, U=2, S=2, A=4 -> score 8.3.
  for (var d = 0; d < 6; d++) {
    final day = monday.addDays(d);
    meals
      ..seed(
        DateTime(day.year, day.month, day.day, 8),
        kind: MealKind.main,
        tags: const MealTags(protein: true, veg: MealVeg.some),
      )
      ..seed(
        DateTime(day.year, day.month, day.day, 13),
        kind: MealKind.main,
        tags: MealTags(protein: d < 5, veg: d < 4 ? MealVeg.halfOrMore : null),
      )
      ..seed(
        DateTime(day.year, day.month, day.day, 20),
        kind: MealKind.main,
        tags: MealTags(
          protein: d < 4,
          veg: d < 3 ? MealVeg.some : null,
          processed: d < 2 ? MealProcessed.mostly : null,
          sugar: d < 2,
          alcohol: d == 4 ? MealAlcohol.threeOrMore : null,
        ),
        last: true,
      );
  }
}

List<Override> _overrides({
  required MealStore meals,
  GoalStore? goals,
  bool foodOn = true,
}) => [
  moduleStoreProvider.overrideWithValue(
    InMemoryModuleStore({if (foodOn) ModuleId.food}),
  ),
  clockProvider.overrideWithValue(() => _now),
  mealStoreProvider.overrideWithValue(meals),
  photoStoreProvider.overrideWithValue(InMemoryPhotoStore()),
  mealCameraProvider.overrideWithValue(FakeMealCamera()),
  foodNightsProvider.overrideWith((ref) async => const []),
  goalStoreProvider.overrideWithValue(goals ?? InMemoryGoalStore()),
];

Future<void> _pumpPlate(
  WidgetTester tester, {
  MealStore? meals,
  GoalStore? goals,
  bool foodOn = true,
}) => pumpScaled(
  tester,
  screenHost(const FoodPlateScreen()),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  size: const Size(360, 2200),
  overrides: _overrides(
    meals: meals ?? TestMealStore(),
    goals: goals,
    foodOn: foodOn,
  ),
);

void main() {
  group('route, Food gate, and navigation from FoodWeekScreen', () {
    test('AppPaths.foodPlate is /today/food/plate', () {
      expect(AppPaths.foodPlate, '/today/food/plate');
    });

    testWidgets('disabled food module renders empty gated FoodPlateScreen', (
      tester,
    ) async {
      final meals = TestMealStore();
      _seedPrototypeWeek(meals, _w1Monday);

      await _pumpPlate(tester, meals: meals, foodOn: false);

      expect(find.byKey(FoodPlateKeys.summaryCard), findsNothing);
      expect(find.byKey(FoodPlateKeys.weeksCard), findsNothing);
      expect(find.byKey(FoodPlateKeys.softModeCard), findsNothing);
    });

    testWidgets('tapping Plate card on FoodWeekScreen navigates to '
        '/today/food/plate in both PlatePattern and PlateBuilding', (
      tester,
    ) async {
      final meals = TestMealStore();
      _seedPrototypeWeek(meals, _w1Monday);
      final container = await pumpOnboardingApp(
        tester,
        store: InMemoryOnboardingStore(completed: true),
        overrides: [
          ...bleOverrides(),
          ...ringOverrides(),
          ...onboardingOverrides(),
          ..._overrides(meals: meals),
        ],
      );

      container.read(appRouterProvider).go(AppPaths.foodWeek);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(FoodWeekKeys.plateCard),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(FoodWeekKeys.plateCard));
      await tester.pumpAndSettle();

      expect(
        container.read(appRouterProvider).state.uri.path,
        AppPaths.foodPlate,
      );
      expect(find.byType(FoodPlateScreen), findsOneWidget);
      expect(find.byKey(FoodPlateKeys.score), findsOneWidget);
    });
  });

  group('FoodPlateScreen content, soft mode, math, and error states', () {
    testWidgets('PlatePattern renders score, 5 components, 4 weeks, plugged-in'
        ' formula, Our choice card, and zero band words', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();
      _seedPrototypeWeek(meals, _w1Monday);
      // Seed w2..w4 building with different counts.
      for (var d = 0; d < 4; d++) {
        final day = _w2Monday.addDays(d);
        meals.seed(
          DateTime(day.year, day.month, day.day, 12),
          kind: MealKind.main,
          tags: const MealTags(protein: true),
          last: true,
        );
      }

      await _pumpPlate(tester, meals: meals);

      final f = MetricFormat.of(tester.element(find.byType(FoodPlateScreen)));
      expect(find.byKey(FoodPlateKeys.lead), findsOneWidget);
      expect(find.byKey(FoodPlateKeys.summaryCard), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(FoodPlateKeys.score)).data, '8.3');
      expect(find.text(l10n.foodPlateOfTen), findsOneWidget);
      expect(find.text(l10n.foodPlateMainsInDays(18, 6)), findsOneWidget);

      for (var i = 0; i < 5; i++) {
        expect(find.byKey(FoodPlateKeys.component(i)), findsOneWidget);
      }
      expect(find.textContaining(l10n.foodPlateCompProtein), findsOneWidget);
      expect(find.textContaining('15 of 18'), findsOneWidget);
      expect(find.textContaining('2.7 of 3'), findsOneWidget);
      expect(find.text(l10n.foodPlateDisclaimer), findsOneWidget);

      expect(find.byKey(FoodPlateKeys.weeksCard), findsOneWidget);
      expect(find.byKey(FoodPlateKeys.weekRow(_w1Monday)), findsOneWidget);
      expect(find.byKey(FoodPlateKeys.weekRow(_w2Monday)), findsOneWidget);
      expect(find.byKey(FoodPlateKeys.weekRow(_w3Monday)), findsOneWidget);
      expect(find.byKey(FoodPlateKeys.weekRow(_w4Monday)), findsOneWidget);
      expect(find.text(l10n.foodPlateWeekShort(4, 4)), findsOneWidget);
      expect(find.text(l10n.foodPlateWeekShort(0, 0)), findsNWidgets(2));
      expect(find.text(l10n.foodPlateWeeksNote(5, 10)), findsOneWidget);

      expect(find.byKey(FoodPlateKeys.ruleCard), findsOneWidget);
      final expr = tester
          .widget<Text>(find.byKey(FoodPlateKeys.ruleExpression))
          .data!;
      expect(
        expr,
        foodPlateExpression(
          f,
          platePattern(
            monday: _w1Monday,
            meals: [for (final m in meals.rows) m.entry],
          ),
        ),
      );
      expect(expr, allOf(contains('2.67'), contains('2.61'), contains('8.3')));
      expect(find.text(l10n.foodPlateRuleNote), findsOneWidget);

      expect(find.byKey(FoodPlateKeys.oursCard), findsOneWidget);
      expect(find.text(l10n.foodPlateOurs1), findsOneWidget);
      expect(find.text(l10n.foodPlateOurs2), findsOneWidget);

      // No band words anywhere on the screen.
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final s = (t.data ?? '').toLowerCase();
        expect(s, isNot(contains('excellent')));
        expect(s, isNot(contains('optimal')));
      }
    });

    testWidgets('PlateBuilding renders building progress and general formula', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore()
        ..seed(
          DateTime(2026, 11, 9, 12),
          kind: MealKind.main,
          tags: const MealTags(protein: true),
          last: true,
        );

      await _pumpPlate(tester, meals: meals);

      expect(find.byKey(FoodPlateKeys.score), findsNothing);
      expect(find.text(l10n.foodPlateBuilding(5, 10, 1, 1)), findsOneWidget);
      final expr = tester
          .widget<Text>(find.byKey(FoodPlateKeys.ruleExpression))
          .data!;
      expect(expr, allOf(contains('0.3'), contains('0.9'), contains('1.5')));
    });

    testWidgets('direct route in soft mode hides all Plate data behind '
        'softModeCard', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();
      _seedPrototypeWeek(meals, _w1Monday);
      final goals = InMemoryGoalStore();
      await goals.addScreening(
        const GoalScreening(
          on: LocalDate(2026, 11, 1),
          softMode: true,
          pregnantOrBreastfeeding: null,
        ),
      );

      await _pumpPlate(tester, meals: meals, goals: goals);

      expect(find.byKey(FoodPlateKeys.softModeCard), findsOneWidget);
      expect(find.text(l10n.foodWeekSoftTitle), findsOneWidget);
      expect(find.text(l10n.foodWeekSoftBody), findsOneWidget);
      expect(find.byKey(FoodPlateKeys.summaryCard), findsNothing);
      expect(find.byKey(FoodPlateKeys.weeksCard), findsNothing);
      expect(find.byKey(FoodPlateKeys.ruleCard), findsNothing);
      expect(find.byKey(FoodPlateKeys.score), findsNothing);
    });

    testWidgets('MealStore error renders metricLoadError', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _pumpPlate(tester, meals: const _ThrowingMealStore());
      expect(find.text(l10n.metricLoadError), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
