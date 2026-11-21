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
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_formula_screen.dart';
import 'package:open_ring/features/food/presentation/food_plate_screen.dart';
import 'package:open_ring/features/food/presentation/food_week_screen.dart';
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

final class _NoReadMealStore implements MealStore {
  const new();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected MealStore call: ${invocation.memberName}');
}

List<Override> _routerOverrides({bool foodOn = true, MealStore? mealStore}) => [
  moduleStoreProvider.overrideWithValue(
    InMemoryModuleStore({if (foodOn) ModuleId.food}),
  ),
  clockProvider.overrideWithValue(() => _now),
  mealStoreProvider.overrideWithValue(mealStore ?? TestMealStore()),
  photoStoreProvider.overrideWithValue(InMemoryPhotoStore()),
  mealCameraProvider.overrideWithValue(FakeMealCamera()),
  foodNightsProvider.overrideWith((ref) async => const []),
  goalStoreProvider.overrideWithValue(InMemoryGoalStore()),
];

void main() {
  group('route and navigation links', () {
    test('AppPaths.foodFormula is /today/food/formula', () {
      expect(AppPaths.foodFormula, '/today/food/formula');
    });

    testWidgets('appRouterProvider routes /today/food/formula even when Food '
        'is disabled and reads no MealStore', (tester) async {
      final container = await pumpOnboardingApp(
        tester,
        store: InMemoryOnboardingStore(completed: true),
        overrides: [
          ...bleOverrides(),
          ...ringOverrides(),
          ...onboardingOverrides(),
          ..._routerOverrides(
            foodOn: false,
            mealStore: const _NoReadMealStore(),
          ),
        ],
      );

      container.read(appRouterProvider).go(AppPaths.foodFormula);
      await tester.pumpAndSettle();

      expect(find.byType(FoodFormulaScreen), findsOneWidget);
      expect(find.byKey(FoodFormulaKeys.intro), findsOneWidget);
      expect(find.byKey(FoodFormulaKeys.meal), findsOneWidget);
    });

    testWidgets('tapping formulaLink on FoodWeekScreen and FoodPlateScreen '
        'navigates to FoodFormulaScreen', (tester) async {
      final container = await pumpOnboardingApp(
        tester,
        store: InMemoryOnboardingStore(completed: true),
        overrides: [
          ...bleOverrides(),
          ...ringOverrides(),
          ...onboardingOverrides(),
          ..._routerOverrides(),
        ],
      );

      container.read(appRouterProvider).go(AppPaths.foodWeek);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(FoodWeekKeys.formulaLink),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(FoodWeekKeys.formulaLink));
      await tester.pumpAndSettle();

      expect(
        container.read(appRouterProvider).state.uri.path,
        AppPaths.foodFormula,
      );
      expect(find.byType(FoodFormulaScreen), findsOneWidget);

      container.read(appRouterProvider).go(AppPaths.foodPlate);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(FoodPlateKeys.formulaLink),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(FoodPlateKeys.formulaLink));
      await tester.pumpAndSettle();

      expect(
        container.read(appRouterProvider).state.uri.path,
        AppPaths.foodFormula,
      );
      expect(find.byType(FoodFormulaScreen), findsOneWidget);
    });
  });

  group('FoodFormulaScreen content and constants', () {
    testWidgets('renders all sections, exact metrics constants, and zero AI '
        'or Weekly energy copy', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await pumpScaled(
        tester,
        screenHost(const FoodFormulaScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        size: const Size(360, 8000),
      );

      final f = MetricFormat.of(tester.element(find.byType(FoodFormulaScreen)));

      expect(find.byKey(FoodFormulaKeys.intro), findsOneWidget);
      expect(find.byKey(FoodFormulaKeys.meal), findsOneWidget);
      expect(find.byKey(FoodFormulaKeys.complete), findsOneWidget);
      expect(find.byKey(FoodFormulaKeys.timing), findsOneWidget);
      expect(find.byKey(FoodFormulaKeys.comparisons), findsOneWidget);
      expect(find.byKey(FoodFormulaKeys.plate), findsOneWidget);
      expect(find.byKey(FoodFormulaKeys.sources), findsOneWidget);
      expect(find.byKey(FoodFormulaKeys.ours), findsOneWidget);
      expect(find.byKey(FoodFormulaKeys.unchecked), findsOneWidget);
      expect(find.byKey(FoodFormulaKeys.cannot), findsOneWidget);
      expect(find.byKey(FoodFormulaKeys.estimate), findsOneWidget);

      expect(
        find.text(
          l10n.foodFormulaMealBody(
            f.clock(DateTime.utc(2026, 1, 1, foodDayStartHour), Duration.zero),
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('10:30'), findsOneWidget);
      expect(find.textContaining('15:00'), findsOneWidget);
      expect(find.textContaining('18:00'), findsOneWidget);
      expect(find.textContaining('23:00'), findsOneWidget);
      expect(find.textContaining('2 bpm'), findsOneWidget);
      expect(find.textContaining(' 5%,'), findsOneWidget);
      expect(find.textContaining('15 min'), findsOneWidget);
      expect(find.textContaining('0.3'), findsOneWidget);
      expect(find.textContaining('0.9'), findsOneWidget);
      expect(find.textContaining('1.5'), findsOneWidget);
      expect(find.text(l10n.foodFormulaUnchecked1), findsOneWidget);
      expect(find.text(l10n.foodFormulaCannot1), findsOneWidget);
      expect(find.text(l10n.metricEstimateNote), findsOneWidget);

      // Zero AI photo or Weekly energy copy belongs in F10b.
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final s = (t.data ?? '').toLowerCase();
        expect(s, isNot(contains('7,700')));
        expect(s, isNot(contains('weekly energy')));
        expect(s, isNot(contains('taco')));
      }
    });
  });
}
