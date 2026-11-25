import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/food/application/food_energy.dart';
import 'package:open_ring/features/food/application/food_energy_gate.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/domain/meal_analysis_store.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';

import '../food_fakes.dart';

// W1: Sunday 2026-12-06, window 2026-11-02 to 2026-12-06, seen on Tuesday.
const _sunday = LocalDate(2026, 12, 6);
const _start = LocalDate(2026, 11, 2);
const _monday = LocalDate(2026, 11, 30);
const ({String model, int outputSchema, int promptVersion, String providerHost})
_target = (providerHost: 'h', model: 'm', promptVersion: 1, outputSchema: 3);

final class _Analyses implements MealAnalysisStore {
  final Map<int, List<MealAnalysis>> rows = {};
  int reads = 0;

  @override
  Future<Map<int, List<MealAnalysis>>> byMeals(Set<int> mealIds) async {
    reads++;
    return {for (final id in mealIds) id: ?rows[id]};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected: ${invocation.memberName}');
}

MealAnalysisItem _item(int id, FoodGroup group, int grams, {bool ok = true}) =>
    (
      id: id,
      name: group.name,
      measure: MealPhotoMeasure.unit,
      countX2: 2,
      grams: grams,
      origin: MealItemOrigin.model,
      confirmed: ok,
      group: group,
    );

MealAnalysis _row(
  int id,
  int mealId,
  List<MealAnalysisItem> items, {
  MealAnalysisStatus status = MealAnalysisStatus.done,
  MealAnalysisTarget target = _target,
}) => (
  id: id,
  mealId: mealId,
  photoName: 'p$mealId.jpg',
  status: status,
  target: target,
  queuedAt: DateTime.utc(2026, 11),
  updatedAt: DateTime.utc(2026, 11),
  sent: null,
  resultJson: null,
  rawText: null,
  confidence: null,
  attempts: 1,
  errorKind: null,
  hiddenOil: false,
  hiddenSauce: false,
  hiddenSugar: false,
  items: items,
);

// 1800 = 1200 g at 150; 1700 = 800 g at 150 plus 125 g at 400.
List<MealAnalysisItem> _itemsFor(LocalDate day, {bool ok = true}) =>
    day.compareTo(_monday) < 0
    ? [_item(1, FoodGroup.other, 1200, ok: ok)]
    : [_item(1, FoodGroup.other, 800), _item(2, FoodGroup.sweet, 125, ok: ok)];

final class _W1 {
  new({Set<LocalDate> stepless = const {}}) {
    for (var i = 0; i < foodEnergyWindowDays; i++) {
      final day = _start.addDays(i);
      if (i % 7 == 6) continue;
      final meal = meals.seed(
        DateTime(day.year, day.month, day.day, 12),
        kind: MealKind.main,
        last: true,
        photo: 'p.jpg',
      );
      mealOf[day] = meal.id;
      analyses.rows[meal.id] = [_row(meal.id, meal.id, _itemsFor(day))];
    }
    container = ProviderContainer.test(
      overrides: [
        clockProvider.overrideWithValue(() => DateTime(2026, 12, 8, 12)),
        foodEnergyGateProvider.overrideWith((ref) async => gate),
        mealStoreProvider.overrideWithValue(meals),
        mealAnalysisStoreProvider.overrideWithValue(analyses),
        weighInsProvider.overrideWith((ref) async => _weighIns()),
        energyDayProvider.overrideWith((ref, date) async {
          ringReads.add(date);
          final steps = stepless.contains(date) ? 0.0 : 500.0;
          return EnergyDayEstimate(
            resting: 1500,
            base: 2500 - steps,
            steps: steps,
            workouts: 0,
          );
        }),
        activeGoalProvider.overrideWith((ref) async => null),
      ],
    );
  }

  final meals = TestMealStore();
  final analyses = _Analyses();
  final Map<LocalDate, int> mealOf = {};
  final List<LocalDate> ringReads = [];
  FoodEnergyGate gate = const FoodEnergyOn(LocalDate(2026, 10, 1));
  late final ProviderContainer container;

  Future<FoodEnergyView> read() => container.read(foodEnergyProvider.future);

  void replace(LocalDate day, MealAnalysis row) =>
      analyses.rows[mealOf[day]!] = [row];
}

List<WeighIn> _weighIns() => [
  for (var i = foodEnergyWindowDays - 1; i >= 0; i--)
    if (i % 5 != 4)
      WeighIn(
        id: i + 1,
        at: _at(_start.addDays(i), 7),
        offsetMinutes: localOffset(_at(_start.addDays(i), 7)),
        kilograms: 80.0 - 0.03 * i,
        source: WeighInSource.manual,
      ),
];

DateTime _at(LocalDate day, int hour) =>
    DateTime(day.year, day.month, day.day, hour).toUtc();

FoodEnergyReady _ready(FoodEnergyView view) => view.result! as FoodEnergyReady;

void main() {
  test('W1 from the stores gives exactly the F1 figures and counts', () async {
    final view = await _W1().read();

    final ready = _ready(view);
    final f = ready.figures;
    expect(ready.counts.sunday, _sunday);
    expect(ready.counts.days, 30);
    expect(ready.counts.weekDays, 6);
    expect(ready.counts.weighIns, 28);
    expect(ready.counts.ringDays, 35);
    expect(f.slopeKgPerDay, closeTo(-0.03, 1e-6));
    expect(f.logMean, closeTo(1780, 1e-6));
    expect(f.weekMean, closeTo(1700, 1e-6));
    expect(f.previousMean, closeTo(1800, 1e-6));
    expect(f.ringMean, closeTo(2500, 1e-6));
    expect(f.balance, closeTo(-231, 1e-6));
    expect(f.expenditureLog, closeTo(2011, 1e-6));
    expect(f.factorLow, closeTo(1.056688, 1e-6));
    expect(f.factorHigh, closeTo(1.429637, 1e-6));
    expect((f.weekLow, f.weekHigh), (1800, 2450));
    expect(f.gapDirection, FoodEnergyGapDirection.under);
    expect(f.gapLow, closeTo(5.365, 1e-3));
    expect(f.gapHigh, closeTo(30.052, 1e-3));
    expect(f.changeDirection, FoodEnergyChangeDirection.none);
    expect(f.changeLow, closeTo(-292.96, 1e-2));
    expect(f.changeHigh, closeTo(44.33, 1e-2));
  });

  test(
    'removing one confirmation in the shown week drops weekDays to 5',
    () async {
      final w = _W1();
      const day = LocalDate(2026, 12, 2);
      w.replace(day, _row(99, w.mealOf[day]!, _itemsFor(day, ok: false)));

      final view = await w.read();

      expect(view.result!.counts.weekDays, 5);
      expect(view.result!.counts.days, 29);
    },
  );

  test('a schema 1 row drops its day', () async {
    final w = _W1();
    const day = LocalDate(2026, 11, 3);
    w.replace(
      day,
      _row(
        99,
        w.mealOf[day]!,
        _itemsFor(day),
        target: (
          providerHost: 'h',
          model: 'm',
          promptVersion: 1,
          outputSchema: 1,
        ),
      ),
    );

    expect((await w.read()).result!.counts.days, 29);
  });

  test(
    'the newest done items row decides, a failed row is passed over',
    () async {
      final w = _W1();
      const day = LocalDate(2026, 11, 3);
      final meal = w.mealOf[day]!;
      w.analyses.rows[meal] = [
        _row(5, meal, _itemsFor(day, ok: false)),
        _row(7, meal, _itemsFor(day)),
        _row(9, meal, const [], status: MealAnalysisStatus.failed),
      ];

      expect((await w.read()).result!.counts.days, 30);
    },
  );

  test('ring days without steps or workouts are left out', () async {
    final w = _W1(
      stepless: {
        const LocalDate(2026, 11, 4),
        const LocalDate(2026, 11, 5),
        const LocalDate(2026, 11, 6),
      },
    );

    expect((await w.read()).result!.counts.ringDays, 32);
  });

  test('a second target in the window holds the week', () async {
    final w = _W1();
    const day = LocalDate(2026, 11, 3);
    w.replace(
      day,
      _row(
        99,
        w.mealOf[day]!,
        _itemsFor(day),
        target: (
          providerHost: 'h',
          model: 'm2',
          promptVersion: 1,
          outputSchema: 3,
        ),
      ),
    );

    final result = (await w.read()).result;

    expect(
      result,
      isA<FoodEnergyHold>()
          .having((h) => h.reason, 'reason', FoodEnergyHoldReason.modelChanged)
          .having((h) => h.last, 'last', isNull),
    );
  });

  test('it reads 63 dates of ring data at most, one store read', () async {
    final w = _W1();

    await w.read();

    expect(w.ringReads.toSet(), hasLength(foodEnergyReadDays));
    expect(foodEnergyReadDays, 63);
    expect(
      w.ringReads.reduce((a, b) => a.compareTo(b) < 0 ? a : b),
      _sunday.addDays(-62),
    );
    expect(w.ringReads.reduce((a, b) => a.compareTo(b) > 0 ? a : b), _sunday);
    expect(w.analyses.reads, 1);
  });

  test('offered also gives the counts the need rows show', () async {
    final w = _W1()..gate = const FoodEnergyOffered(_sunday);

    final view = await w.read();

    expect(view.gate, isA<FoodEnergyOffered>());
    expect(view.result!.counts.weighIns, 28);
  });

  for (final gate in const <FoodEnergyGate>[
    FoodEnergyHidden(),
    FoodEnergyDemo(),
    FoodEnergyBlocked(FoodEnergyBlock.softMode),
    FoodEnergyNeedsScreening(),
  ]) {
    test('${gate.runtimeType} reads no data', () async {
      final w = _W1()..gate = gate;

      final view = await w.read();

      expect(view.gate, same(gate));
      expect(view.result, isNull);
      expect(w.ringReads, isEmpty);
      expect(w.analyses.reads, 0);
    });
  }
}
