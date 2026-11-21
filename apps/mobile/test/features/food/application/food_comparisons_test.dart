import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/food_comparisons.dart';
import 'package:open_ring/features/food/application/food_nights.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

import '../food_fakes.dart';

final _now = DateTime(2026, 11, 17, 21); // Tue; Monday = 2026-11-16

final class _CountingMealStore implements MealStore {
  final TestMealStore inner = TestMealStore();
  LocalDate? lastFrom;
  LocalDate? lastTo;
  int betweenCalls = 0;

  @override
  Future<List<Meal>> between(LocalDate from, LocalDate to) {
    betweenCalls++;
    lastFrom = from;
    lastTo = to;
    return inner.between(from, to);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected call: ${invocation.memberName}');
}

final class _ThrowingMealStore implements MealStore {
  @override
  Future<List<Meal>> between(LocalDate from, LocalDate to) =>
      Future.error(StateError('db broken'));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected call: ${invocation.memberName}');
}

Future<ProviderContainer> _container({
  Set<ModuleId> modules = const {ModuleId.food},
  MealStore? meals,
  Future<List<FoodNight>> Function(Ref ref)? nights,
}) async {
  final container = ProviderContainer.test(
    overrides: [
      moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
      clockProvider.overrideWithValue(() => _now),
      if (meals != null) mealStoreProvider.overrideWithValue(meals),
      foodNightsProvider.overrideWith(nights ?? (ref) async => const []),
    ],
  );
  await container.read(enabledModulesProvider.future);
  return container;
}

void main() {
  group('foodComparisonsProvider', () {
    test(
      'returns empty collecting view when Food disabled and reads zero stores',
      () async {
        final meals = _CountingMealStore();
        var nightCalls = 0;
        final container = await _container(
          modules: const {},
          meals: meals,
          nights: (ref) async {
            nightCalls++;
            return const [];
          },
        );

        final view = await container.read(foodComparisonsProvider.future);
        expect(meals.betweenCalls, 0);
        expect(nightCalls, 0);
        expect(view.items, hasLength(5));
        expect(view.items.every((item) => item.lead is LinkCollecting), isTrue);
        expect(view.regularity, isA<RegularityCollecting>());
      },
    );

    test('queries closed 90-day Monday-to-Sunday window and excludes '
        'current week', () async {
      final meals = _CountingMealStore();
      final container = await _container(meals: meals);

      final view = await container.read(foodComparisonsProvider.future);
      expect(meals.betweenCalls, 1);
      expect(meals.lastFrom, const LocalDate(2026, 8, 18));
      expect(meals.lastTo, const LocalDate(2026, 11, 15));
      expect(view.firstNight, const LocalDate(2026, 8, 18));
      expect(view.lastNight, const LocalDate(2026, 11, 15));
      expect(view.updatedMonday, const LocalDate(2026, 11, 16));
    });

    test('propagates MealStore errors', () async {
      final container = await _container(meals: _ThrowingMealStore());

      await expectLater(
        container.read(foodComparisonsProvider.future),
        throwsStateError,
      );
    });

    test('propagates foodNightsProvider errors', () async {
      final meals = _CountingMealStore();
      final container = await _container(
        meals: meals,
        nights: (ref) =>
            Future<List<FoodNight>>.error(StateError('nights broken')),
      );

      await expectLater(
        container.read(foodComparisonsProvider.future),
        throwsStateError,
      );
    });

    test('re-reads when dataRevisionProvider bumps', () async {
      final meals = _CountingMealStore();
      final container = await _container(meals: meals);

      await container.read(foodComparisonsProvider.future);
      expect(meals.betweenCalls, 1);
      container.read(dataRevisionProvider.notifier).bump();
      await container.read(foodComparisonsProvider.future);
      expect(meals.betweenCalls, 2);
    });

    test('computes 5 links in prototype order, matching pairs, leadSd, leadT99, '
        'and MealRegularity', () {
      final store = TestMealStore();
      final nights = <FoodNight>[];
      // Build 14 lateLastMeal pairs across 7 weekday blocks (Mon-Thu) plus
      // weekend completeness for MealRegularity.
      var cursor = const LocalDate(2026, 9, 14); // Monday
      for (var w = 0; w < 8; w++) {
        for (var offset = 0; offset < 4; offset += 2) {
          final expDay = cursor.addDays(offset);
          final ctlDay = cursor.addDays(offset + 1);
          // Exposed: 07:30 first, 22:30 last -> onset 23:30 (60m gap), HR 67.
          store
            ..seed(
              DateTime(expDay.year, expDay.month, expDay.day, 7, 30),
              kind: MealKind.main,
              tags: const MealTags(protein: true),
            )
            ..seed(
              DateTime(expDay.year, expDay.month, expDay.day, 22, 30),
              kind: MealKind.main,
              tags: const MealTags(veg: MealVeg.halfOrMore),
              last: true,
            );
          nights.add(
            FoodNight(
              day: expDay,
              heartRate: 67.0 + (w % 2),
              hrv: 40,
              sleepOnset: DateTime.utc(
                expDay.year,
                expDay.month,
                expDay.day,
                23,
                30,
              ),
            ),
          );
          // Control: 07:30 first, 19:00 last -> onset 23:00 (240m gap), HR 58.
          store
            ..seed(
              DateTime(ctlDay.year, ctlDay.month, ctlDay.day, 7, 30),
              kind: MealKind.main,
              tags: const MealTags(protein: true),
            )
            ..seed(
              DateTime(ctlDay.year, ctlDay.month, ctlDay.day, 19),
              kind: MealKind.main,
              tags: const MealTags(veg: MealVeg.halfOrMore),
              last: true,
            );
          nights.add(
            FoodNight(
              day: ctlDay,
              heartRate: 58,
              hrv: 48,
              sleepOnset: DateTime.utc(
                ctlDay.year,
                ctlDay.month,
                ctlDay.day,
                23,
              ),
            ),
          );
        }
        // Add Saturday and Sunday at 09:30 for weekend regularity shift.
        final sat = cursor.addDays(5);
        store.seed(
          DateTime(sat.year, sat.month, sat.day, 9, 30),
          kind: MealKind.main,
          tags: const MealTags(protein: true),
          last: true,
        );
        cursor = cursor.addDays(7);
      }

      final view = buildFoodComparisonsView(
        today: _now.date,
        nights: nights,
        meals: store.rows,
      );
      expect(
        [for (final i in view.items) i.link],
        const [
          FoodLink.alcoholThreeOrMore,
          FoodLink.lateLastMeal,
          FoodLink.caffeineAfter14,
          FoodLink.heavyDinner,
          FoodLink.alcoholOneToTwo,
        ],
      );

      final late = view.items[1];
      expect(late.leadOutcome, NightOutcome.heartRate);
      expect(late.alsoOutcome, NightOutcome.hrv);
      expect(late.alcoholLink, isFalse);
      expect(late.lead, isA<LinkPattern>());
      expect(late.leadPairs, hasLength(late.lead.pairs));
      expect(late.leadSd, isNotNull);
      expect(late.leadT99, closeTo(t99(late.lead.pairs - 1), 1e-9));

      final reg = view.regularity;
      expect(reg, isA<MealRegularity>());
      final r = reg as MealRegularity;
      expect(r.completeDays, regularityDays);
      expect(r.weekendLaterMinutes, closeTo(120.0, 0.1));
    });
  });
}

extension on DateTime {
  LocalDate get date => LocalDate(year, month, day);
}
