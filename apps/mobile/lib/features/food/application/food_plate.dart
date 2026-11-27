import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/food_day.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/goals/application/goal_intake_providers.dart';

const foodPlateHistoryWeeks = 4;

final class FoodPlateWeek {
  const new({required this.monday, required this.sunday, required this.plate});

  final LocalDate monday;
  final LocalDate sunday;
  final PlateResult plate;
}

final class FoodPlateView {
  const new({required this.softMode, required this.weeks});

  final bool softMode;
  final List<FoodPlateWeek> weeks;

  FoodPlateWeek get current => weeks.first;
}

FoodPlateView buildFoodPlateView({
  required LocalDate latestMonday,
  required List<Meal> meals,
  required bool softMode,
}) {
  final entries = [for (final m in meals) m.entry];
  final weeks = [
    for (var i = 0; i < foodPlateHistoryWeeks; i++)
      FoodPlateWeek(
        monday: latestMonday.addDays(-7 * i),
        sunday: latestMonday.addDays(-7 * i + 6),
        plate: platePattern(
          monday: latestMonday.addDays(-7 * i),
          meals: entries,
        ),
      ),
  ];
  return FoodPlateView(softMode: softMode, weeks: List.unmodifiable(weeks));
}

final foodPlateProvider = FutureProvider<FoodPlateView>((ref) async {
  final latestMonday = mondayOf(ref.watch(currentFoodDayProvider)).addDays(-7);
  if (!ref.watch(foodEnabledProvider)) {
    return buildFoodPlateView(
      latestMonday: latestMonday,
      meals: const [],
      softMode: false,
    );
  }
  ref.watch(dataRevisionProvider);
  final soft = (await ref.watch(softModeProvider.future)) ?? false;
  final firstMonday = latestMonday.addDays(-7 * (foodPlateHistoryWeeks - 1));
  final lastSunday = latestMonday.addDays(6);
  final meals = await ref
      .watch(mealStoreProvider)
      .between(firstMonday, lastSunday);
  return buildFoodPlateView(
    latestMonday: latestMonday,
    meals: meals,
    softMode: soft,
  );
});
