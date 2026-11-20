import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/food_plate.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

import '../food_fakes.dart';

const _w1Monday = LocalDate(2026, 11, 9);
const _w2Monday = LocalDate(2026, 11, 2);
const _w3Monday = LocalDate(2026, 10, 26);
const _w4Monday = LocalDate(2026, 10, 19);
final _tuesday = DateTime(2026, 11, 17, 12);

final class _RecordingMealStore implements MealStore {
  new(this.inner);

  final TestMealStore inner;
  LocalDate? lastFrom;
  LocalDate? lastTo;
  bool throwOnBetween = false;

  @override
  Future<List<Meal>> between(LocalDate from, LocalDate to) {
    lastFrom = from;
    lastTo = to;
    if (throwOnBetween) return Future.error(StateError('meal read error'));
    return inner.between(from, to);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected: ${invocation.memberName}');
}

final class _ThrowingGoalStore implements GoalStore {
  const new();

  @override
  Future<List<GoalScreening>> screenings() =>
      Future.error(StateError('goal read error'));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected: ${invocation.memberName}');
}

void _seedQualifiedWeek(
  TestMealStore meals,
  LocalDate monday, {
  bool high = true,
}) {
  // 6 complete days, 3 mains per day = 18 mains.
  for (var d = 0; d < 6; d++) {
    final day = monday.addDays(d);
    meals
      ..seed(
        DateTime(day.year, day.month, day.day, 8),
        kind: MealKind.main,
        tags: MealTags(
          protein: high,
          veg: high ? MealVeg.some : null,
          processed: !high && d < 4 ? MealProcessed.mostly : null,
        ),
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
          protein: high && d < 4,
          veg: d < 3 ? MealVeg.some : null,
          processed: high && d < 2 ? MealProcessed.mostly : null,
          sugar: high ? d < 2 : d < 4,
          alcohol: high && d == 4 ? MealAlcohol.threeOrMore : null,
        ),
        last: true,
      );
  }
}

Future<ProviderContainer> _container({
  required DateTime now,
  Set<ModuleId> modules = const {ModuleId.food},
  MealStore? meals,
  GoalStore? goals,
}) async {
  final container = ProviderContainer.test(
    overrides: [
      clockProvider.overrideWithValue(() => now),
      moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
      if (meals != null) mealStoreProvider.overrideWithValue(meals),
      if (goals != null) goalStoreProvider.overrideWithValue(goals),
    ],
  );
  await container.read(enabledModulesProvider.future);
  return container;
}

void main() {
  group('buildFoodPlateView and foodPlateProvider', () {
    test(
      'returns 4 empty building weeks when food module is disabled',
      () async {
        final container = await _container(
          now: _tuesday,
          modules: const {},
          meals: _RecordingMealStore(TestMealStore()),
          goals: const _ThrowingGoalStore(),
        );

        final view = await container.read(foodPlateProvider.future);

        expect(view.softMode, isFalse);
        expect(view.weeks, hasLength(4));
        expect(view.current.monday, _w1Monday);
        expect(view.current.sunday, const LocalDate(2026, 11, 15));
        expect(view.weeks[1].monday, _w2Monday);
        expect(view.weeks[2].monday, _w3Monday);
        expect(view.weeks[3].monday, _w4Monday);
        for (final w in view.weeks) {
          expect(w.plate, isA<PlateBuilding>());
        }
      },
    );

    test('queries the 4 closed weeks in one between call and scores '
        'qualified vs building weeks including untagged exclusion', () async {
      final raw = TestMealStore();
      // Prototype-equivalent qualified week for w1: 6 days, 18 mains:
      // P=15, V=13, U=2, S=2, A=4 -> score 8.3.
      _seedQualifiedWeek(raw, _w1Monday);
      // Untagged record on day 0 must be ignored by platePattern (never a main).
      raw.seed(DateTime(_w1Monday.year, _w1Monday.month, _w1Monday.day, 15));
      // w2: qualified lower week.
      _seedQualifiedWeek(raw, _w2Monday, high: false);
      // w3: only 4 complete days -> PlateBuilding.
      for (var d = 0; d < 4; d++) {
        final day = _w3Monday.addDays(d);
        raw
          ..seed(
            DateTime(day.year, day.month, day.day, 12),
            kind: MealKind.main,
            tags: const MealTags(protein: true),
          )
          ..seed(
            DateTime(day.year, day.month, day.day, 19),
            kind: MealKind.main,
            tags: const MealTags(protein: true),
            last: true,
          );
      }
      final recorder = _RecordingMealStore(raw);
      final container = await _container(
        now: _tuesday,
        meals: recorder,
        goals: InMemoryGoalStore(),
      );

      final view = await container.read(foodPlateProvider.future);

      expect(recorder.lastFrom, _w4Monday);
      expect(recorder.lastTo, const LocalDate(2026, 11, 15));
      expect(view.softMode, isFalse);
      expect(view.weeks, hasLength(4));

      final w1 = view.weeks[0].plate as PlatePattern;
      expect(w1.completeDays, 6);
      expect(w1.mains, 18);
      expect(w1.protein, 15);
      expect(w1.veg, 13);
      expect(w1.processed, 2);
      expect(w1.sugaryDays, 2);
      expect(w1.drinks, 4.0);
      expect(w1.score, 8.3);

      expect(view.weeks[1].plate, isA<PlatePattern>());
      final w3 = view.weeks[2].plate as PlateBuilding;
      expect(w3.completeDays, 4);
      expect(w3.mains, 8);
      final w4 = view.weeks[3].plate as PlateBuilding;
      expect(w4.completeDays, 0);
      expect(w4.mains, 0);
    });

    test('handles 05:00 Monday boundary and revision invalidation', () async {
      final raw = TestMealStore();
      _seedQualifiedWeek(raw, _w2Monday);
      final container = await _container(
        now: DateTime(2026, 11, 16, 4, 30),
        meals: raw,
        goals: InMemoryGoalStore(),
      );

      final before = await container.read(foodPlateProvider.future);
      expect(before.current.monday, _w2Monday);

      raw.seed(
        DateTime(2026, 11, 2, 16),
        kind: MealKind.main,
        tags: const MealTags(protein: true),
      );
      container.read(dataRevisionProvider.notifier).bump();
      final after = await container.read(foodPlateProvider.future);
      expect((after.current.plate as PlatePattern).mains, 19);
    });

    test(
      'reads softModeProvider and propagates MealStore/GoalStore errors',
      () async {
        final goals = InMemoryGoalStore();
        await goals.addScreening(
          const GoalScreening(
            on: LocalDate(2026, 11, 10),
            softMode: true,
            pregnantOrBreastfeeding: null,
          ),
        );
        final softContainer = await _container(
          now: _tuesday,
          meals: TestMealStore(),
          goals: goals,
        );
        final softView = await softContainer.read(foodPlateProvider.future);
        expect(softView.softMode, isTrue);

        final badMeals = await _container(
          now: _tuesday,
          meals: _RecordingMealStore(TestMealStore())..throwOnBetween = true,
          goals: InMemoryGoalStore(),
        );
        await expectLater(
          badMeals.read(foodPlateProvider.future),
          throwsStateError,
        );

        final badGoals = await _container(
          now: _tuesday,
          meals: TestMealStore(),
          goals: const _ThrowingGoalStore(),
        );
        await expectLater(
          badGoals.read(foodPlateProvider.future),
          throwsStateError,
        );
      },
    );
  });
}
