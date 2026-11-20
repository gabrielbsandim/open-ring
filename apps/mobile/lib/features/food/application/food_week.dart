import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/food_day.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/application/food_nights.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/goals/application/goal_intake_providers.dart';

final class FoodWeekDayView {
  const new({
    required this.date,
    required this.meals,
    required this.complete,
    required this.sleepOnset,
    required this.windowMinutes,
    required this.gapMinutes,
  });

  final LocalDate date;
  final List<Meal> meals;
  final bool complete;
  final DateTime? sleepOnset;
  final double? windowMinutes;
  final double? gapMinutes;
}

final class FoodWeekView {
  const new({
    required this.monday,
    required this.sunday,
    required this.stats,
    required this.plate,
    required this.softMode,
    required this.days,
    required this.completeWindows,
    required this.completeGaps,
  });

  final LocalDate monday;
  final LocalDate sunday;
  final FoodWeek stats;
  final PlateResult plate;
  final bool softMode;
  final List<FoodWeekDayView> days;
  final List<double> completeWindows;
  final List<double> completeGaps;
}

const _daysPerWeek = 7;

FoodWeekView buildFoodWeekView({
  required LocalDate monday,
  required List<Meal> meals,
  required Map<LocalDate, DateTime> sleepOnsets,
  required bool softMode,
}) {
  final sunday = monday.addDays(_daysPerWeek - 1);
  final byDay = <LocalDate, List<Meal>>{};
  for (final meal in meals) {
    final day = foodDay(meal.entry.at);
    final offset = day.daysSince(monday);
    if (offset >= 0 && offset < _daysPerWeek) (byDay[day] ??= []).add(meal);
  }
  final days = [
    for (var i = 0; i < _daysPerWeek; i++)
      _dayView(
        monday.addDays(i),
        _sorted(byDay[monday.addDays(i)] ?? const []),
        sleepOnsets[monday.addDays(i)],
      ),
  ];
  final windows = [
    for (final d in days)
      if (d.complete && d.windowMinutes != null) d.windowMinutes!,
  ]..sort();
  final gaps = [
    for (final d in days)
      if (d.complete && d.gapMinutes != null) d.gapMinutes!,
  ]..sort();
  final entries = [for (final m in meals) m.entry];
  return FoodWeekView(
    monday: monday,
    sunday: sunday,
    stats: foodWeek(monday: monday, meals: entries, sleepOnsets: sleepOnsets),
    plate: platePattern(monday: monday, meals: entries),
    softMode: softMode,
    days: List.unmodifiable(days),
    completeWindows: List.unmodifiable(windows),
    completeGaps: List.unmodifiable(gaps),
  );
}

List<Meal> _sorted(List<Meal> raw) {
  final copy = [...raw]
    ..sort((a, b) {
      final t = a.entry.at.compareTo(b.entry.at);
      return t != 0 ? t : a.id.compareTo(b.id);
    });
  return List.unmodifiable(copy);
}

FoodWeekDayView _dayView(LocalDate date, List<Meal> meals, DateTime? onset) {
  final entries = [for (final m in meals) m.entry];
  final opening = [
    for (final e in entries)
      if (opensWindow(e)) e.at,
  ]..sort();
  final gap = opening.isEmpty || onset == null
      ? null
      : lastMealToSleep(entries, onset);
  double? mins(Duration? d) =>
      d == null ? null : d.inMicroseconds / Duration.microsecondsPerMinute;
  return FoodWeekDayView(
    date: date,
    meals: meals,
    complete: meals.any((m) => m.last),
    sleepOnset: onset,
    windowMinutes: opening.isEmpty
        ? null
        : mins(opening.last.difference(opening.first)),
    gapMinutes: mins(gap),
  );
}

final foodWeekProvider = FutureProvider<FoodWeekView>((ref) async {
  final monday = mondayOf(ref.watch(currentFoodDayProvider)).addDays(-7);
  if (!ref.watch(foodEnabledProvider)) {
    return buildFoodWeekView(
      monday: monday,
      meals: const [],
      sleepOnsets: const {},
      softMode: false,
    );
  }
  ref.watch(dataRevisionProvider);
  final sunday = monday.addDays(_daysPerWeek - 1);
  final meals = await ref.watch(mealStoreProvider).between(monday, sunday);
  final soft = (await ref.watch(softModeProvider.future)) ?? false;
  var nights = const <FoodNight>[];
  try {
    nights = await ref.watch(foodNightsProvider.future);
  } on Object {
    // Sleep or ring history failure leaves diary and Plate pattern usable.
  }
  return buildFoodWeekView(
    monday: monday,
    meals: meals,
    sleepOnsets: sleepOnsetsOf(nights),
    softMode: soft,
  );
});
