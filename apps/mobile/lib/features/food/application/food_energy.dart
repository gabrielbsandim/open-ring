import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/ai/domain/meal_photo_prompt.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/food/application/food_day.dart';
import 'package:open_ring/features/food/application/food_energy_gate.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/domain/goal.dart';

/// The days one result reads: the window of the latest week and the
/// [foodEnergyLookbackWeeks] windows before it.
const int foodEnergyReadDays =
    foodEnergyWindowDays + 7 * foodEnergyLookbackWeeks;

final class FoodEnergyView {
  const new({required this.gate, this.result});

  final FoodEnergyGate gate;

  /// Null unless the gate is offered or on.
  final FoodEnergyResult? result;
}

/// The `host|model|prompt|schema` key a model change is detected by.
String foodEnergyTarget(MealAnalysisTarget t) =>
    '${t.providerHost}|${t.model}|${t.promptVersion}|${t.outputSchema}';

/// The meal's log from its newest done items row, or null unless that row
/// has items and every one is confirmed.
FoodEnergyMeal foodEnergyMeal(Meal meal, List<MealAnalysis> rows) {
  final itemsSchema = mealPhotoOutputSchemaVersion(withItems: true);
  final done = [
    for (final row in rows)
      if (row.status == MealAnalysisStatus.done &&
          row.target.outputSchema == itemsSchema)
        row,
  ]..sort((a, b) => b.id.compareTo(a.id));
  final row = done.firstOrNull;
  if (row == null || row.items.isEmpty) return _unlogged(meal);
  if (row.items.any((item) => !item.confirmed)) return _unlogged(meal);
  final log = mealLogKcal(
    [for (final item in row.items) (group: item.group, grams: item.grams)],
    oil: row.hiddenOil,
    sauce: row.hiddenSauce,
    sugar: row.hiddenSugar,
  );
  return (
    entry: meal.entry,
    logKcal: log,
    target: foodEnergyTarget(row.target),
  );
}

FoodEnergyMeal _unlogged(Meal meal) =>
    (entry: meal.entry, logKcal: null, target: null);

final foodEnergyProvider = FutureProvider<FoodEnergyView>((ref) async {
  final gate = await ref.watch(foodEnergyGateProvider.future);
  if (gate is! FoodEnergyOn && gate is! FoodEnergyOffered) {
    return FoodEnergyView(gate: gate);
  }
  ref
    ..watch(dataRevisionProvider)
    ..watch(mealAnalysisRevisionProvider);
  final latestSunday = mondayOf(ref.watch(currentFoodDayProvider)).addDays(-1);
  final from = latestSunday.addDays(1 - foodEnergyReadDays);
  final dates = [for (var i = 0; i < foodEnergyReadDays; i++) from.addDays(i)];
  final meals = await ref.watch(mealStoreProvider).between(from, latestSunday);
  final rows = await ref.watch(mealAnalysisStoreProvider).byMeals({
    for (final meal in meals) meal.id,
  });
  final logged = [
    for (final meal in meals) foodEnergyMeal(meal, rows[meal.id] ?? const []),
  ];
  final weight = await ref.watch(weightSummaryProvider.future);
  final ringDays = await Future.wait([
    for (final date in dates) ref.watch(energyDayProvider(date).future),
  ]);
  final goal = await ref.watch(activeGoalProvider.future);
  final result = foodEnergyLatest(
    latestSunday: latestSunday,
    days: [for (final date in dates) ?foodEnergyDay(date, logged)],
    weighIns: weight?.daily ?? const [],
    ring: [
      for (final (i, day) in ringDays.indexed)
        if (day is EnergyDayEstimate && energyDayOnRecord(day))
          (date: dates[i], value: day.total),
    ],
    goalBlockStart: _blockStart(goal),
  );
  return FoodEnergyView(gate: gate, result: result);
});

LocalDate? _blockStart(Goal? goal) {
  if (goal == null || goal.phase != GoalPhase.block) return null;
  if (goal.blockAnchorKg == null) return null;
  return goal.blockStartedOn;
}
