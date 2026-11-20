import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/food_day.dart';
import 'package:open_ring/features/food/application/food_nights.dart';
import 'package:open_ring/features/food/application/food_week.dart';
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

const _monday = LocalDate(2026, 11, 9);
const _sunday = LocalDate(2026, 11, 15);
const _priorMonday = LocalDate(2026, 11, 2);
const _priorSunday = LocalDate(2026, 11, 8);
final _tuesdayNoon = DateTime(2026, 11, 17, 12);

final class _ThrowingBetweenMealStore implements MealStore {
  const new();

  @override
  Future<List<Meal>> between(LocalDate from, LocalDate to) =>
      Future.error(StateError('meal store error'));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected: ${invocation.memberName}');
}

final class _ThrowingGoalStore implements GoalStore {
  int calls = 0;

  @override
  Future<List<GoalScreening>> screenings() async {
    calls++;
    throw StateError('goal store error');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected: ${invocation.memberName}');
}

Meal _meal(
  int id,
  LocalDate date,
  int hour,
  int minute, {
  MealKind? kind = MealKind.main,
  MealTags tags = const MealTags(),
  bool last = false,
}) {
  final at = DateTime.utc(date.year, date.month, date.day, hour, minute);
  return Meal(
    id: id,
    at: at,
    offsetMinutes: 0,
    createdAt: at,
    kind: kind,
    tags: tags,
    last: last,
  );
}

DateTime _onset(LocalDate date, int hour, int minute) =>
    DateTime.utc(date.year, date.month, date.day, hour, minute);

Future<ProviderContainer> _container({
  required DateTime now,
  Set<ModuleId> modules = const {ModuleId.food},
  MealStore? meals,
  List<FoodNight>? nights,
  GoalStore? goals,
  List<Override> extra = const [],
}) async {
  final container = ProviderContainer.test(
    overrides: [
      clockProvider.overrideWithValue(() => now),
      moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
      if (meals != null) mealStoreProvider.overrideWithValue(meals),
      if (nights != null)
        foodNightsProvider.overrideWith((ref) async => nights),
      if (goals != null) goalStoreProvider.overrideWithValue(goals),
      ...extra,
    ],
  );
  await container.read(enabledModulesProvider.future);
  return container;
}

void main() {
  group('1. off-gate', () {
    test(
      'foodEnabledProvider == false returns empty FoodWeekView without reading '
      'mealStoreProvider, foodNightsProvider, or goalStoreProvider',
      () async {
        final reads = StoreReads();
        var nightsRead = false;
        final goalStore = _ThrowingGoalStore();
        final container = await _container(
          now: _tuesdayNoon,
          modules: const {},
          goals: goalStore,
          extra: [
            ...reads.overrides(),
            foodNightsProvider.overrideWith((ref) {
              nightsRead = true;
              throw StateError('must not read foodNightsProvider');
            }),
          ],
        );

        final view = await container.read(foodWeekProvider.future);

        expect(reads.meals, isFalse);
        expect(nightsRead, isFalse);
        expect(goalStore.calls, 0);
        expect(view.stats.completeDays, 0);
        expect(view.stats.records, 0);
        expect(view.stats.windowMinutes, isNull);
        expect(view.stats.gapMinutes, isNull);
        expect(view.plate, isA<PlateBuilding>());
        expect(view.plate.completeDays, 0);
        expect(view.plate.mains, 0);
        expect(view.softMode, isFalse);
        expect(view.completeWindows, isEmpty);
        expect(view.completeGaps, isEmpty);
        expect(view.days.expand((day) => day.meals), isEmpty);
      },
    );
  });

  group('2. closed week boundary at 05:00', () {
    test('at Monday 2026-11-16 01:30 local, foodDay is Sunday 2026-11-15 so '
        'closed week is 2026-11-02..2026-11-08', () async {
      final meals = TestMealStore()
        ..seed(DateTime(2026, 11, 5, 12), kind: MealKind.main, last: true)
        ..seed(DateTime(2026, 11, 12, 12), kind: MealKind.main, last: true);
      final container = await _container(
        now: DateTime(2026, 11, 16, 1, 30),
        meals: meals,
        nights: const [],
        goals: InMemoryGoalStore(),
      );

      expect(
        container.read(currentFoodDayProvider),
        const LocalDate(2026, 11, 15),
      );
      final view = await container.read(foodWeekProvider.future);

      expect(view.monday, _priorMonday);
      expect(view.sunday, _priorSunday);
      expect(view.days, hasLength(7));
      expect(view.days.first.date, _priorMonday);
      expect(view.days.last.date, _priorSunday);
      expect(view.stats.records, 1);
      expect(view.stats.completeDays, 1);
      expect(view.days[3].meals, hasLength(1));
    });

    test('at Monday 2026-11-16 05:00 local, foodDay is Monday 2026-11-16 so '
        'closed week rolls to 2026-11-09..2026-11-15', () async {
      final meals = TestMealStore()
        ..seed(DateTime(2026, 11, 5, 12), kind: MealKind.main, last: true)
        ..seed(DateTime(2026, 11, 12, 12), kind: MealKind.main, last: true);
      final container = await _container(
        now: DateTime(2026, 11, 16, 5),
        meals: meals,
        nights: const [],
        goals: InMemoryGoalStore(),
      );

      expect(
        container.read(currentFoodDayProvider),
        const LocalDate(2026, 11, 16),
      );
      final view = await container.read(foodWeekProvider.future);

      expect(view.monday, _monday);
      expect(view.sunday, _sunday);
      expect(view.days, hasLength(7));
      expect(view.days.first.date, _monday);
      expect(view.days.last.date, _sunday);
      expect(view.stats.records, 1);
      expect(view.stats.completeDays, 1);
      expect(view.days[3].meals, hasLength(1));
    });
  });

  group('3. post-midnight 00:30 Sunday-night meal and ordering', () {
    test('2026-11-16 00:30 meal belongs to days[6] (2026-11-15), sorts after '
        'Sunday 21:00, extends windowMinutes, and counts in stats.records while '
        '04:30 prior-week and 05:00 next-week meals are excluded', () async {
      final meals = TestMealStore()
        ..seed(DateTime(2026, 11, 9, 4, 30), kind: MealKind.snack, last: true)
        ..seed(DateTime(2026, 11, 15, 12), kind: MealKind.main)
        ..seed(DateTime(2026, 11, 15, 21), kind: MealKind.main)
        ..seed(DateTime(2026, 11, 16, 0, 30), kind: MealKind.snack, last: true)
        ..seed(DateTime(2026, 11, 16, 5), kind: MealKind.main, last: true);
      final container = await _container(
        now: _tuesdayNoon,
        meals: meals,
        nights: const [],
        goals: InMemoryGoalStore(),
      );

      final view = await container.read(foodWeekProvider.future);
      final sundayView = view.days[6];

      expect(view.monday, _monday);
      expect(view.sunday, _sunday);
      expect(view.days[0].meals, isEmpty);
      expect(sundayView.date, _sunday);
      expect(sundayView.meals, hasLength(3));
      expect(sundayView.meals.map((meal) => meal.entry.at).toList(), [
        DateTime.utc(2026, 11, 15, 12),
        DateTime.utc(2026, 11, 15, 21),
        DateTime.utc(2026, 11, 16, 0, 30),
      ]);
      expect(sundayView.complete, isTrue);
      expect(sundayView.windowMinutes, 750.0);
      expect(view.stats.records, 3);
      expect(view.stats.completeDays, 1);
      expect(view.stats.windowMinutes, 750.0);
    });

    test(
      'buildFoodWeekView sorts unsorted meals including 00:30 after 21:00 on '
      'days[6] and excludes prior-week 04:30 and next-week 05:00 meals',
      () {
        final view = buildFoodWeekView(
          monday: _monday,
          meals: [
            _meal(1, const LocalDate(2026, 11, 16), 0, 30, last: true),
            _meal(2, _sunday, 21, 0),
            _meal(3, _sunday, 12, 0),
            _meal(4, _monday, 4, 30, last: true),
            _meal(5, const LocalDate(2026, 11, 16), 5, 0, last: true),
          ],
          sleepOnsets: const {},
          softMode: false,
        );

        expect(view.stats.records, 3);
        expect(view.days[0].meals, isEmpty);
        expect(view.days[6].meals.map((meal) => meal.id).toList(), [3, 2, 1]);
        expect(view.days[6].windowMinutes, 750.0);
      },
    );
  });

  group('4. plain drinks (opensWindow == false)', () {
    test(
      'complete day with only plain unsweetened drinks keeps meals and '
      'records, marks complete true, leaves windowMinutes and gapMinutes '
      'null, and contributes nothing to completeWindows or completeGaps',
      () async {
        final view = buildFoodWeekView(
          monday: _monday,
          meals: [
            _meal(
              1,
              _monday,
              7,
              30,
              kind: MealKind.drink,
              tags: const MealTags(caffeine: true),
            ),
            _meal(2, _monday, 14, 0, kind: MealKind.drink, last: true),
          ],
          sleepOnsets: {_monday: _onset(_monday, 23, 0)},
          softMode: false,
        );

        final mondayView = view.days[0];
        expect(mondayView.meals, hasLength(2));
        expect(mondayView.complete, isTrue);
        expect(mondayView.sleepOnset, _onset(_monday, 23, 0));
        expect(mondayView.windowMinutes, isNull);
        expect(mondayView.gapMinutes, isNull);
        expect(view.stats.completeDays, 1);
        expect(view.stats.records, 2);
        expect(view.stats.windowMinutes, isNull);
        expect(view.stats.gapMinutes, isNull);
        expect(view.completeWindows, isEmpty);
        expect(view.completeGaps, isEmpty);
      },
    );
  });

  group('5. meal logged after sleepOnset', () {
    test(
      'complete day with meals at 08:00 and 23:30 and sleepOnset 23:00 gives '
      'windowMinutes 930.0 and gapMinutes 900.0 from 08:00',
      () {
        final view = buildFoodWeekView(
          monday: _monday,
          meals: [
            _meal(1, _monday, 8, 0),
            _meal(2, _monday, 23, 30, kind: MealKind.snack, last: true),
          ],
          sleepOnsets: {_monday: _onset(_monday, 23, 0)},
          softMode: false,
        );

        final mondayView = view.days[0];
        expect(mondayView.windowMinutes, 930.0);
        expect(mondayView.gapMinutes, 900.0);
        expect(view.completeWindows, [930.0]);
        expect(view.completeGaps, [900.0]);
      },
    );

    test(
      'complete day whose only window meal is at 23:30 after sleepOnset 23:00 '
      'gives windowMinutes 0.0, gapMinutes null, and '
      'completeGaps.length < completeWindows.length',
      () {
        final view = buildFoodWeekView(
          monday: _monday,
          meals: [_meal(1, _monday, 23, 30, last: true)],
          sleepOnsets: {_monday: _onset(_monday, 23, 0)},
          softMode: false,
        );

        final mondayView = view.days[0];
        expect(mondayView.windowMinutes, 0.0);
        expect(mondayView.gapMinutes, isNull);
        expect(view.completeWindows, [0.0]);
        expect(view.completeGaps, isEmpty);
        expect(view.completeGaps.length, lessThan(view.completeWindows.length));
        expect(view.stats.windowMinutes, 0.0);
        expect(view.stats.gapMinutes, isNull);
      },
    );
  });

  group('6. complete vs incomplete days and missing sleepOnset', () {
    test('complete day missing sleepOnset populates completeWindows only, '
        'incomplete day populates day view only, and completeWindows and '
        'completeGaps are sorted ascending', () {
      final tuesday = _monday.addDays(1);
      final wednesday = _monday.addDays(2);
      final thursday = _monday.addDays(3);
      final view = buildFoodWeekView(
        monday: _monday,
        meals: [
          _meal(1, _monday, 8, 0),
          _meal(2, _monday, 20, 0, last: true),
          _meal(3, tuesday, 10, 0),
          _meal(4, tuesday, 19, 0, last: true),
          _meal(5, wednesday, 9, 0),
          _meal(6, wednesday, 19, 30, last: true),
          _meal(7, thursday, 7, 0),
          _meal(8, thursday, 22, 0),
        ],
        sleepOnsets: {
          _monday: _onset(_monday, 23, 0),
          tuesday: _onset(tuesday, 23, 0),
          thursday: _onset(thursday, 23, 0),
        },
        softMode: false,
      );

      expect(view.days[0].complete, isTrue);
      expect(view.days[0].windowMinutes, 720.0);
      expect(view.days[0].gapMinutes, 180.0);

      expect(view.days[1].complete, isTrue);
      expect(view.days[1].windowMinutes, 540.0);
      expect(view.days[1].gapMinutes, 240.0);

      expect(view.days[2].complete, isTrue);
      expect(view.days[2].sleepOnset, isNull);
      expect(view.days[2].windowMinutes, 630.0);
      expect(view.days[2].gapMinutes, isNull);

      expect(view.days[3].complete, isFalse);
      expect(view.days[3].sleepOnset, _onset(thursday, 23, 0));
      expect(view.days[3].windowMinutes, 900.0);
      expect(view.days[3].gapMinutes, 60.0);

      expect(view.completeWindows, [540.0, 630.0, 720.0]);
      expect(view.completeGaps, [180.0, 240.0]);
      expect(view.stats.completeDays, 3);
      expect(view.stats.records, 8);
      expect(view.stats.windowMinutes, 630.0);
      expect(view.stats.gapMinutes, 210.0);
    });
  });

  group('7. error and soft mode semantics on foodWeekProvider', () {
    test(
      'foodNightsProvider throwing degrades to empty sleepOnsets so meals and '
      'PlatePattern still resolve',
      () async {
        final meals = TestMealStore();
        for (var i = 0; i < 5; i++) {
          final day = DateTime(2026, 11, 9 + i);
          meals.seed(
            DateTime(day.year, day.month, day.day, 12),
            kind: MealKind.main,
            tags: const MealTags(protein: true, veg: MealVeg.some),
          );
          meals.seed(
            DateTime(day.year, day.month, day.day, 19),
            kind: MealKind.main,
            tags: const MealTags(protein: true, veg: MealVeg.halfOrMore),
            last: true,
          );
        }
        final container = await _container(
          now: _tuesdayNoon,
          meals: meals,
          goals: InMemoryGoalStore(),
          extra: [
            foodNightsProvider.overrideWith(
              (ref) => Future<List<FoodNight>>.error(StateError('sleep error')),
            ),
          ],
        );

        final view = await container.read(foodWeekProvider.future);

        expect(view.stats.completeDays, 5);
        expect(view.stats.records, 10);
        expect(view.plate, isA<PlatePattern>());
        expect(view.plate.completeDays, 5);
        expect(view.plate.mains, 10);
        expect(view.completeWindows, [420.0, 420.0, 420.0, 420.0, 420.0]);
        expect(view.completeGaps, isEmpty);
        expect(
          view.days.every(
            (day) => day.sleepOnset == null && day.gapMinutes == null,
          ),
          isTrue,
        );
      },
    );

    test('mealStoreProvider.between throwing propagates AsyncError', () async {
      final container = await _container(
        now: _tuesdayNoon,
        meals: const _ThrowingBetweenMealStore(),
        nights: const [],
        goals: InMemoryGoalStore(),
      );

      await expectLater(
        container.read(foodWeekProvider.future),
        throwsA(isA<StateError>()),
      );
      expect(container.read(foodWeekProvider), isA<AsyncError<FoodWeekView>>());
    });

    test('goalStoreProvider.screenings throwing propagates AsyncError without '
        'defaulting softMode to false', () async {
      final container = await _container(
        now: _tuesdayNoon,
        meals: TestMealStore(),
        nights: const [],
        goals: _ThrowingGoalStore(),
      );

      await expectLater(
        container.read(foodWeekProvider.future),
        throwsA(isA<StateError>()),
      );
      expect(container.read(foodWeekProvider), isA<AsyncError<FoodWeekView>>());
    });

    test(
      'GoalScreening softMode true sets softMode true even when Goals module '
      'is off, and newer false clears it',
      () async {
        final goals = InMemoryGoalStore();
        await goals.addScreening(
          const GoalScreening(
            on: LocalDate(2026, 11, 10),
            softMode: true,
            pregnantOrBreastfeeding: null,
          ),
        );
        final container = await _container(
          now: _tuesdayNoon,
          modules: const {ModuleId.food},
          meals: TestMealStore(),
          nights: const [],
          goals: goals,
        );

        final first = await container.read(foodWeekProvider.future);
        expect(first.softMode, isTrue);

        await goals.addScreening(
          const GoalScreening(
            on: LocalDate(2026, 11, 12),
            softMode: false,
            pregnantOrBreastfeeding: null,
          ),
        );
        container.read(dataRevisionProvider.notifier).bump();

        final second = await container.read(foodWeekProvider.future);
        expect(second.softMode, isFalse);
      },
    );

    test(
      'dataRevisionProvider.notifier.bump refreshes foodWeekProvider',
      () async {
        final meals = TestMealStore();
        final container = await _container(
          now: _tuesdayNoon,
          meals: meals,
          nights: const [],
          goals: InMemoryGoalStore(),
        );

        final before = await container.read(foodWeekProvider.future);
        expect(before.stats.records, 0);

        meals.seed(DateTime(2026, 11, 10, 12), kind: MealKind.main, last: true);
        container.read(dataRevisionProvider.notifier).bump();

        final after = await container.read(foodWeekProvider.future);
        expect(after.stats.records, 1);
        expect(after.stats.completeDays, 1);
      },
    );
  });
}
