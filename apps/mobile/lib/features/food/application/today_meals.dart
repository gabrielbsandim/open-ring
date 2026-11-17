import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';

final class FoodToday {
  const new({required this.count, this.windowFrom});

  final int count;

  /// The wall clock of the first meal that opens the eating window.
  final DateTime? windowFrom;
}

FoodToday foodToday(List<Meal> meals) {
  final opening = [
    for (final meal in meals)
      if (opensWindow(meal.entry)) meal.entry.at,
  ]..sort();
  return FoodToday(count: meals.length, windowFrom: opening.firstOrNull);
}

/// The meals of the food day of now, which turns at 05:00.
final todayMealsProvider = FutureProvider<List<Meal>>((ref) {
  ref.watch(dataRevisionProvider);
  final now = ref.watch(clockProvider)().toLocal();
  final today = foodDay(now);
  final next = today.addDays(1);
  // currentDateProvider rolls at midnight, so the 05:00 turn needs its own.
  final roll = Timer(
    DateTime(next.year, next.month, next.day, foodDayStartHour).difference(now),
    ref.invalidateSelf,
  );
  ref.onDispose(roll.cancel);
  return ref.watch(mealStoreProvider).between(today, today);
});
