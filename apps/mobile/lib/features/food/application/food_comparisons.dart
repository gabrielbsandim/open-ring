import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/food_day.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/application/food_nights.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';

final class FoodComparisonPair {
  const new({
    required this.exposedDay,
    required this.controlDay,
    required this.diff,
    this.exposedHeartRate,
    this.controlHeartRate,
    this.exposedOnset,
    this.controlOnset,
  });

  final LocalDate exposedDay;
  final LocalDate controlDay;
  final double? exposedHeartRate;
  final double? controlHeartRate;
  final DateTime? exposedOnset;
  final DateTime? controlOnset;
  final double diff;
}

final class FoodComparisonItem {
  const new({
    required this.link,
    required this.leadOutcome,
    required this.alsoOutcome,
    required this.alcoholLink,
    required this.lead,
    required this.also,
    required this.leadPairs,
    this.leadSd,
    this.leadT99,
  });

  final FoodLink link;
  final NightOutcome leadOutcome;
  final NightOutcome alsoOutcome;
  final bool alcoholLink;
  final LinkComparison lead;
  final LinkComparison also;
  final List<FoodComparisonPair> leadPairs;
  final double? leadSd;
  final double? leadT99;
}

final class FoodComparisonsView {
  const new({
    required this.firstNight,
    required this.lastNight,
    required this.updatedMonday,
    required this.items,
    required this.regularity,
  });

  final LocalDate firstNight;
  final LocalDate lastNight;
  final LocalDate updatedMonday;
  final List<FoodComparisonItem> items;
  final RegularityResult regularity;
}

const List<(FoodLink, NightOutcome, NightOutcome, bool)> _linkSpecs = [
  (FoodLink.alcoholThreeOrMore, NightOutcome.heartRate, NightOutcome.hrv, true),
  (FoodLink.lateLastMeal, NightOutcome.heartRate, NightOutcome.hrv, false),
  (FoodLink.caffeineAfter14, NightOutcome.onset, NightOutcome.heartRate, false),
  (FoodLink.heavyDinner, NightOutcome.heartRate, NightOutcome.hrv, false),
  (FoodLink.alcoholOneToTwo, NightOutcome.heartRate, NightOutcome.hrv, true),
];

double? _onsetMinute(FoodNight night) {
  final onset = night.sleepOnset;
  if (onset == null) return null;
  final date = LocalDate(onset.year, onset.month, onset.day);
  final days = date.daysSince(night.day);
  return days * Duration.minutesPerDay +
      onset.hour * 60 +
      onset.minute +
      onset.second / 60;
}

FoodComparisonPair? _buildLeadPair(
  NightOutcome outcome,
  FoodNight exposed,
  FoodNight control,
) {
  if (outcome == NightOutcome.heartRate) {
    final e = exposed.heartRate;
    final c = control.heartRate;
    if (e == null || c == null) return null;
    return FoodComparisonPair(
      exposedDay: exposed.day,
      controlDay: control.day,
      exposedHeartRate: e,
      controlHeartRate: c,
      diff: e - c,
    );
  }
  final e = _onsetMinute(exposed);
  final c = _onsetMinute(control);
  if (e == null || c == null) return null;
  return FoodComparisonPair(
    exposedDay: exposed.day,
    controlDay: control.day,
    exposedOnset: exposed.sleepOnset,
    controlOnset: control.sleepOnset,
    diff: e - c,
  );
}

double? _sampleSd(List<FoodComparisonPair> pairs) {
  if (pairs.length < 2) return null;
  final mean =
      pairs.fold<double>(0, (sum, pair) => sum + pair.diff) / pairs.length;
  final squares = pairs.fold<double>(
    0,
    (sum, pair) => sum + (pair.diff - mean) * (pair.diff - mean),
  );
  return math.sqrt(squares / (pairs.length - 1));
}

FoodComparisonItem _buildItem({
  required FoodLink link,
  required NightOutcome leadOutcome,
  required NightOutcome alsoOutcome,
  required bool alcoholLink,
  required LocalDate lastNight,
  required Map<LocalDate, FoodNight> byDay,
  required List<FoodNight> nights,
  required List<MealEntry> entries,
}) {
  final pairs = matchPairs(
    link: link,
    lastNight: lastNight,
    nights: nights,
    meals: entries,
  );
  final leadPairs = <FoodComparisonPair>[
    for (final pair in pairs)
      ?_buildLeadPair(leadOutcome, byDay[pair.exposed]!, byDay[pair.control]!),
  ];
  return FoodComparisonItem(
    link: link,
    leadOutcome: leadOutcome,
    alsoOutcome: alsoOutcome,
    alcoholLink: alcoholLink,
    lead: compareLink(
      link: link,
      outcome: leadOutcome,
      lastNight: lastNight,
      nights: nights,
      meals: entries,
    ),
    also: compareLink(
      link: link,
      outcome: alsoOutcome,
      lastNight: lastNight,
      nights: nights,
      meals: entries,
    ),
    leadPairs: List.unmodifiable(leadPairs),
    leadSd: _sampleSd(leadPairs),
    leadT99: leadPairs.length >= 2 ? t99(leadPairs.length - 1) : null,
  );
}

FoodComparisonsView buildFoodComparisonsView({
  required LocalDate today,
  required List<FoodNight> nights,
  required List<Meal> meals,
}) {
  final firstNight = foodFirstNight(today);
  final lastNight = foodCompareLastNight(today);
  final entries = [for (final m in meals) m.entry];
  final byDay = {for (final n in nights) n.day: n};
  final items = [
    for (final (link, lead, also, alcoholLink) in _linkSpecs)
      _buildItem(
        link: link,
        leadOutcome: lead,
        alsoOutcome: also,
        alcoholLink: alcoholLink,
        lastNight: lastNight,
        byDay: byDay,
        nights: nights,
        entries: entries,
      ),
  ];
  return FoodComparisonsView(
    firstNight: firstNight,
    lastNight: lastNight,
    updatedMonday: mondayOf(today),
    items: List.unmodifiable(items),
    regularity: mealRegularity(meals: entries),
  );
}

final foodComparisonsProvider = FutureProvider<FoodComparisonsView>((
  ref,
) async {
  final today = ref.watch(currentFoodDayProvider);
  if (!ref.watch(foodEnabledProvider)) {
    return buildFoodComparisonsView(
      today: today,
      nights: const [],
      meals: const [],
    );
  }
  ref.watch(dataRevisionProvider);
  final first = foodFirstNight(today);
  final last = foodCompareLastNight(today);
  final meals = await ref.watch(mealStoreProvider).between(first, last);
  final nights = await ref.watch(foodNightsProvider.future);
  return buildFoodComparisonsView(today: today, nights: nights, meals: meals);
});
