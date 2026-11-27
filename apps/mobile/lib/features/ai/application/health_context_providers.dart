import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/food/application/food_week.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/application/sleep_source_selection.dart';
import 'package:open_ring/features/sleep/domain/imported_sleep_reader.dart';
import 'package:open_ring/features/today/application/readiness_trend.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/trends/application/trends_providers.dart';
import 'package:open_ring/features/trends/domain/trend_history.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/application/workout_source_selection.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';

final aiReplyLanguageProvider = Provider<String>(
  (ref) => aiLanguageTag(PlatformDispatcher.instance.locale),
);

String aiLanguageTag(Locale locale) =>
    locale.languageCode == 'pt' && locale.countryCode != null
    ? 'pt-${locale.countryCode}'
    : locale.languageCode;

final _aiSourcesProvider = FutureProvider<AiContextSources>((ref) async {
  final config = await ref.watch(aiConfigProvider.future);
  return await _readSources(ref, config);
});

/// Null while the AI module is off, and then no source is read.
final FutureProviderFamily<HealthContextInput?, AiAnalysisKind>
healthContextInputProvider = FutureProvider.family((ref, kind) async {
  if (!ref.watch(aiEnabledProvider)) return null;
  final config = await ref.watch(aiConfigProvider.future);
  return assembleHealthContextInput(
    await ref.watch(_aiSourcesProvider.future),
    detail: config.detailLevel,
    window: config.contextWindow,
    kind: kind,
  );
});

final FutureProviderFamily<AiPayloadResult?, AiAnalysisKind> aiPayloadProvider =
    FutureProvider.family((ref, kind) async {
      final input = await ref.watch(healthContextInputProvider(kind).future);
      if (input == null) return null;
      return buildAiPayloadResult(input);
    });

int _historyDays(AiContextWindow window) =>
    math.min(math.max(window.maxWeeks * 7, window.maxDays), trendHistoryDays);

Future<AiContextSources> _readSources(Ref ref, AiConfig config) async {
  ref.watch(dataRevisionProvider);
  final today = ref.watch(currentDateProvider);
  final now = ref.watch(clockProvider)();
  final imported =
      config.importedIncluded && ref.watch(aiImportedOfferedProvider);
  final days = _historyDays(config.contextWindow);
  final from = now.subtract(Duration(days: days + 2));
  final (modules, profile, hidden, remMeasured, ring) = await (
    ref.watch(enabledModulesProvider.future),
    ref.watch(userProfileProvider.future),
    ref.watch(hideNumbersProvider.future),
    ref.watch(remMeasuredProvider.future),
    ref.watch(ringStatusProvider.future),
  ).wait;
  // With the flag off no imported record reaches the payload. Module providers
  // may still read imported data locally; numbers derived from it stay out.
  const ringOnly = NoImportedSleepReader();
  Future<Map<LocalDate, SleepNight>> nightsOf(ImportedSleepReader other) =>
      readSleepNights(
        ring: ref.watch(sleepHistoryReaderProvider),
        imported: other,
        from: from,
        to: now,
      );
  final (nights, ringNights, activity, own, other) = await (
    nightsOf(imported ? ref.watch(importedSleepReaderProvider) : ringOnly),
    imported
        ? nightsOf(ringOnly)
        : Future.value(const <LocalDate, SleepNight>{}),
    ref
        .watch(activityHistoryReaderProvider)
        .dailyActivity(
          from: today.addDays(1 - days - chronicLoadDays),
          to: today,
        ),
    ref.watch(workoutHistoryReaderProvider).intersecting(from: from, to: now),
    imported
        ? ref
              .watch(importedWorkoutReaderProvider)
              .intersecting(from: from, to: now)
        : Future.value(noImportedWorkouts),
  ).wait;
  final nightList = nights.values.toList();
  final samples = await readNightSamples(
    ref.watch(heartHistoryReaderProvider),
    nightList,
  );
  final history = TrendHistory.collect(
    today: today,
    nights: nightList,
    heartRate: samples.heartRate,
    hrv: samples.hrv,
    spo2: samples.spo2,
    activity: activity,
    sleepGoal: ref.watch(sleepGoalProvider),
    remMeasured: remMeasured,
  );
  final readiness = ReadinessTrend.collect(
    today: today,
    history: history,
    activity: activity,
  );
  final bodyOn = modules.contains(ModuleId.body) && !hidden;
  final weight = bodyOn ? await ref.watch(weightSummaryProvider.future) : null;
  AiSeries of(TrendMetric m) => _byDate(history.values(m));
  return AiContextSources(
    today: today,
    replyLanguage: ref.watch(aiReplyLanguageProvider),
    units: _units(ref.watch(currentUnitSystemProvider)),
    profile: _profile(profile, today.year, ref.watch(stepGoalProvider)),
    hasRing: ring.paired,
    importedIncluded: imported,
    remMeasured: remMeasured,
    nights: nights,
    ringNightDates: (imported ? ringNights : nights).keys.toSet(),
    workouts: selectWorkouts([...own, ...other.workouts], other.priority),
    series: {
      AiDailyMetric.sleepMin: of(TrendMetric.sleepDuration),
      AiDailyMetric.sleepScore: of(TrendMetric.sleepScore),
      AiDailyMetric.rhr: of(TrendMetric.restingHeartRate),
      AiDailyMetric.hrv: of(TrendMetric.hrv),
      AiDailyMetric.spo2: of(TrendMetric.spo2),
      AiDailyMetric.steps: of(TrendMetric.steps),
      AiDailyMetric.activeKcal: {
        for (final d in activity)
          if (d.activeKilocalories > 0) d.date: d.activeKilocalories,
      },
      AiDailyMetric.readiness: {
        for (final (i, v) in readiness.values.indexed)
          if (v != null) readiness.firstDate.addDays(i): v.toDouble(),
      },
      AiDailyMetric.stress: _byDate(
        await ref.watch(dailyStressProvider.future),
      ),
      // Effort, Day Score and Energy already mix in imported records, so they
      // stay out until the flag is on.
      if (imported && modules.contains(ModuleId.effort))
        AiDailyMetric.load: _effortLoad(
          await ref.watch(effortDailyLoadProvider.future),
          today,
        ),
      if (imported && modules.contains(ModuleId.openScore))
        AiDailyMetric.dayScore: _byDate(
          (await ref.watch(dayScoreHistoryProvider.future)).scores,
        ),
      if (weight != null) AiDailyMetric.weight: _byDate(weight.daily),
    },
    weighIns: weight == null ? null : _weighIns(weight, today),
    energy: imported && ref.watch(energyGateProvider) == EnergyGate.on
        ? _energy(await ref.watch(energyWeekProvider.future), today)
        : null,
    food: modules.contains(ModuleId.food)
        ? _food(await ref.watch(foodWeekProvider.future), imported: imported)
        : null,
  );
}

AiSeries _byDate(Iterable<DailyValue> values) => {
  for (final v in values) v.date: v.value,
};

// The Effort list ends yesterday, so its last value belongs to D-1.
AiSeries _effortLoad(List<double> loads, LocalDate today) => {
  for (final (i, v) in loads.indexed) today.addDays(i - loads.length): v,
};

AiUnits _units(UnitSystem system) => switch (system) {
  UnitSystem.metric => const AiUnits(),
  UnitSystem.imperial => const AiUnits(
    distance: AiDistanceUnit.mi,
    weight: AiWeightUnit.lb,
  ),
};

AiProfileInput _profile(UserProfile? p, int year, int stepGoal) =>
    AiProfileInput(
      age: p?.ageIn(year),
      sex: switch (p?.sex) {
        Sex.male => AiBiologicalSex.male,
        Sex.female => AiBiologicalSex.female,
        null => null,
      },
      heightCm: p?.heightCentimeters?.round(),
      maxHr: p?.maxHeartRate,
      stepGoal: stepGoal,
    );

AiWeighInsSummary _weighIns(WeightSummary s, LocalDate today) {
  final rate = s.rate;
  final ready = rate is WeightRateReady ? rate : null;
  final last = LocalDate.fromInstant(
    s.last.at,
    Duration(minutes: s.last.offsetMinutes),
  );
  return AiWeighInsSummary(
    n30: s.daily.where((d) => today.daysSince(d.date) < 30).length,
    trendLastKg: s.trend,
    daysSinceLast: today.daysSince(last),
    kgPerWeek: ready?.perWeek,
    kgPerWeekLow: ready?.low,
    kgPerWeekHigh: ready?.high,
  );
}

// Today is still running, so only finished days feed the usual total.
AiEnergySummary? _energy(List<EnergyWeekDay> week, LocalDate today) {
  final past = [
    for (final d in week)
      if (d.date != today) ?d.day,
  ];
  final usual = energyUsual(past);
  if (usual == null) return null;
  return AiEnergySummary(
    bmrKcal: past.last.resting.round(),
    tdeeKcalAvg7: usual.round(),
  );
}

AiFoodSummary? _food(FoodWeekView view, {required bool imported}) {
  if (view.stats.completeDays == 0) return null;
  return AiFoodSummary(
    completeDays: view.stats.completeDays,
    plateScore: switch (view.plate) {
      PlatePattern(:final score) => score,
      PlateBuilding() => null,
    },
    windowMedianMin: view.stats.windowMinutes?.round(),
    // The gap is measured to a sleep onset that may come from another app.
    lastMealToSleepMin: imported ? view.stats.gapMinutes?.round() : null,
  );
}
