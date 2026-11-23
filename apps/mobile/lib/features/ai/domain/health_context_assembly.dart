import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/health_context_v2.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';

const int aiMinDaysWithData = 5;

/// Every daily series the context can carry, with the fixed label its facts
/// use. These labels are the only free text a built context holds.
enum AiDailyMetric {
  sleepMin('Sleep duration', AiFactUnit.min),
  sleepScore('Sleep score', AiFactUnit.score),
  rhr('Resting heart rate', AiFactUnit.bpm),
  hrv('Heart rate variability', AiFactUnit.ms),
  stress('Stress', AiFactUnit.score),
  spo2('Blood oxygen', AiFactUnit.pct),
  steps('Steps', AiFactUnit.steps),
  activeKcal('Active energy', AiFactUnit.kcal),
  load('Training load', AiFactUnit.points),
  readiness('Readiness', AiFactUnit.score),
  dayScore('Day Score', AiFactUnit.score),
  weight('Weight', AiFactUnit.kg);

  new(this.label, this.unit);

  final String label;
  final AiFactUnit unit;

  AiMetricFamily get family => switch (this) {
    sleepMin || sleepScore => AiMetricFamily.sleep,
    rhr || hrv => AiMetricFamily.heart,
    stress => AiMetricFamily.stress,
    spo2 => AiMetricFamily.oxygen,
    steps || activeKcal || load => AiMetricFamily.activity,
    readiness || dayScore => AiMetricFamily.overall,
    weight => AiMetricFamily.body,
  };

  bool get requiresRing => const {
    rhr,
    hrv,
    stress,
    spo2,
    steps,
    activeKcal,
    readiness,
  }.contains(this);

  bool get minimalAllowed =>
      const {sleepScore, steps, load, readiness, dayScore}.contains(this);

  String get latestLabel => '$label, latest day';
  String get meanLabel => '$label, window mean';
}

typedef AiSeries = Map<LocalDate, double>;

/// What the app already computed, after the module gates and the imported
/// records flag were applied by the reader.
@immutable
final class AiContextSources {
  const new({
    required this.today,
    required this.replyLanguage,
    required this.units,
    required this.profile,
    required this.hasRing,
    required this.importedIncluded,
    this.remMeasured = true,
    this.nights = const {},
    this.ringNightDates = const {},
    this.series = const {},
    this.workouts = const [],
    this.weighIns,
    this.energy,
    this.food,
  });

  final LocalDate today;
  final String replyLanguage;
  final AiUnits units;
  final AiProfileInput profile;
  final bool hasRing;
  final bool importedIncluded;
  final bool remMeasured;
  final Map<LocalDate, SleepNight> nights;
  final Set<LocalDate> ringNightDates;
  final Map<AiDailyMetric, AiSeries> series;
  final List<WorkoutEntry> workouts;
  final AiWeighInsSummary? weighIns;
  final AiEnergySummary? energy;
  final AiFoodSummary? food;
}

@immutable
sealed class AiPayloadResult {
  const new();
}

@immutable
final class AiPayloadReady extends AiPayloadResult {
  const new(this.payload);
  final BuiltAiPayload payload;
}

@immutable
final class AiPayloadNotEnoughData extends AiPayloadResult {
  const new(this.days);
  final int days;
}

AiPayloadResult buildAiPayloadResult(HealthContextInput input) {
  final days = aiDaysWithData(input.days);
  if (days < aiMinDaysWithData) return AiPayloadNotEnoughData(days);
  return AiPayloadReady(HealthContextBuilder.build(input));
}

int aiDaysWithData(List<AiDayRow> rows) => rows.where(_hasData).length;

bool _hasData(AiDayRow r) =>
    _hasRingData(r) ||
    [r.sleepMin, r.sleepScore, r.activeKcal, r.load].any((v) => v != null) ||
    r.readiness != null ||
    r.weightKg != null;

/// Days span the window, oldest first and ending today, one row per calendar
/// day even when empty, because the builder labels rows by position.
HealthContextInput assembleHealthContextInput(
  AiContextSources s, {
  required AiDetailLevel detail,
  required AiContextWindow window,
  AiAnalysisKind kind = AiAnalysisKind.dailyReview,
}) {
  final dates = [
    for (var ago = window.maxDays - 1; ago >= 0; ago--) s.today.addDays(-ago),
  ];
  final days = [for (final d in dates) _dayRow(s, d)];
  return HealthContextInput(
    kind: kind,
    replyLanguage: s.replyLanguage,
    detail: detail,
    window: window,
    units: s.units,
    profile: s.profile,
    coverage: AiCoverageInput(
      hasRing: s.hasRing,
      sleepSource: _sleepSource(s, dates),
      daysWithRingData: days.where(_hasRingData).length,
      importedIncluded: s.importedIncluded,
    ),
    days: days,
    baselines: _baselines(s, dates),
    weeks: [
      for (var w = window.maxWeeks - 1; w >= 0; w--)
        _weekRow(s, s.today.addDays(-7 * w - 6)),
    ],
    workouts: _workouts(s, window.maxDays),
    weighIns: s.weighIns,
    energy: s.energy,
    food: s.food,
    facts: _facts(s, dates),
  );
}

AiDayRow _dayRow(AiContextSources s, LocalDate date) {
  double? v(AiDailyMetric m) => s.series[m]?[date];
  int? n(AiDailyMetric m) => v(m)?.round();
  final night = s.nights[date];
  return AiDayRow(
    date: date,
    weekday: AiWeekday
        .values[DateTime.utc(date.year, date.month, date.day).weekday - 1],
    sleepMin: n(AiDailyMetric.sleepMin),
    sleepScore: n(AiDailyMetric.sleepScore),
    deepMin: _phaseMinutes(night, SleepPhase.deep),
    remMin: s.remMeasured ? _phaseMinutes(night, SleepPhase.rem) : null,
    awakeMin: night?.awake.inMinutes,
    bedtime: _clock(night?.start, night),
    wake: _clock(night?.end, night),
    rhr: _round1(v(AiDailyMetric.rhr)),
    hrv: _round1(v(AiDailyMetric.hrv)),
    stressAvg: _round1(v(AiDailyMetric.stress)),
    spo2Avg: _round1(v(AiDailyMetric.spo2)),
    steps: n(AiDailyMetric.steps),
    activeKcal: n(AiDailyMetric.activeKcal),
    load: n(AiDailyMetric.load),
    readiness: n(AiDailyMetric.readiness),
    weightKg: _round1(v(AiDailyMetric.weight)),
  );
}

bool _hasRingData(AiDayRow r) =>
    [r.rhr, r.hrv, r.stressAvg, r.spo2Avg, r.steps].any((v) => v != null);

AiSleepSource _sleepSource(AiContextSources s, List<LocalDate> dates) {
  if (dates.any(s.ringNightDates.contains)) return AiSleepSource.ring;
  if (dates.any(s.nights.containsKey)) return AiSleepSource.imported;
  return AiSleepSource.none;
}

int? _phaseMinutes(SleepNight? night, SleepPhase phase) {
  if (night == null) return null;
  final total = night.spans
      .where((span) => span.phase == phase)
      .fold(Duration.zero, (sum, span) => sum + span.duration);
  return total.inMinutes;
}

AiClockTime? _clock(DateTime? at, SleepNight? night) {
  if (at == null || night == null) return null;
  final wall = at.toUtc().add(night.spans.last.utcOffset);
  return AiClockTime(wall.hour, wall.minute);
}

AiBaselinesInput _baselines(AiContextSources s, List<LocalDate> dates) {
  List<DailyValue> values(AiDailyMetric m) => [
    for (final MapEntry(:key, :value) in (s.series[m] ?? const {}).entries)
      (date: key, value: value),
  ];
  final sleep = [for (final d in dates) ?s.series[AiDailyMetric.sleepMin]?[d]];
  return AiBaselinesInput(
    rhr: _baselineEntry(
      restingHeartRateBaseline(values(AiDailyMetric.rhr), today: s.today),
    ),
    hrv: _baselineEntry(hrvBaseline(values(AiDailyMetric.hrv), today: s.today)),
    sleepMin: sleep.isEmpty
        ? null
        : AiBaselineEntry(
            value: _mean(sleep).roundToDouble(),
            days: sleep.length,
          ),
  );
}

AiBaselineEntry? _baselineEntry(BaselineResult result) => switch (result) {
  BaselineBuilding() => null,
  BaselineReady(scale: BaselineScale.log, :final meanOnScale, :final days) =>
    AiBaselineEntry(value: _round1(math.exp(meanOnScale))!, days: days),
  BaselineReady(:final meanOnScale, :final days) => AiBaselineEntry(
    value: _round1(meanOnScale)!,
    days: days,
  ),
};

AiWeekRow _weekRow(AiContextSources s, LocalDate first) {
  final dates = [for (var i = 0; i < 7; i++) first.addDays(i)];
  List<double> values(AiDailyMetric m) => [
    for (final d in dates) ?s.series[m]?[d],
  ];
  double? avg(AiDailyMetric m) {
    final found = values(m);
    return found.isEmpty ? null : _round1(_mean(found));
  }

  final loads = values(AiDailyMetric.load);
  return AiWeekRow(
    sleepMinAvg: avg(AiDailyMetric.sleepMin),
    sleepScoreAvg: avg(AiDailyMetric.sleepScore),
    rhrAvg: avg(AiDailyMetric.rhr),
    hrvAvg: avg(AiDailyMetric.hrv),
    stepsAvg: avg(AiDailyMetric.steps),
    loadSum: loads.isEmpty
        ? null
        : loads.fold<double>(0, (a, b) => a + b).round(),
    workouts: s.workouts.where((w) => dates.contains(_dateOf(w))).length,
    readinessAvg: avg(AiDailyMetric.readiness),
    weightAvgKg: avg(AiDailyMetric.weight),
  );
}

List<AiWorkoutRow> _workouts(AiContextSources s, int maxDays) {
  final recent = [
    for (final w in s.workouts)
      if (s.today.daysSince(_dateOf(w)) case final ago
          when ago >= 0 && ago < maxDays)
        w,
  ]..sort((a, b) => b.start.compareTo(a.start));
  return [for (final (i, w) in recent.indexed) _workoutRow(s.today, i, w)];
}

// Imported workouts carry type and time only, and an index id, never the
// record id another app gave them.
AiWorkoutRow _workoutRow(LocalDate today, int index, WorkoutEntry w) {
  final own = w is WorkoutListItem ? w : null;
  final meters = own?.distanceMeters;
  return AiWorkoutRow(
    id: 'wk.${index + 1}',
    daysAgo: today.daysSince(_dateOf(w)),
    date: _dateOf(w),
    type: w.type,
    minutes: w.elapsed.inMinutes,
    avgHr: own?.averageHeartRate,
    distanceKm: meters == null ? null : meters / 1000,
    kcal: own?.activeKilocalories?.round(),
    isImported: own == null,
    sourceApp: own == null ? w.source : null,
  );
}

List<HealthFact> _facts(AiContextSources s, List<LocalDate> dates) => [
  for (final m in AiDailyMetric.values)
    ...switch ([for (final d in dates) ?s.series[m]?[d]]) {
      final found when found.isNotEmpty => [
        _fact(m, 'last', m.latestLabel, found.last, found.length),
        _fact(m, 'avg', m.meanLabel, _mean(found), found.length),
      ],
      _ => const <HealthFact>[],
    },
];

HealthFact _fact(AiDailyMetric m, String id, String label, double v, int n) =>
    HealthFact(
      id: 'f.${m.name}.$id',
      label: label,
      value: _round1(v)!,
      unit: m.unit,
      family: m.family,
      days: n,
      requiresRing: m.requiresRing,
      minimalAllowed: m.minimalAllowed,
    );

LocalDate _dateOf(WorkoutEntry w) =>
    LocalDate.fromInstant(w.start, w.utcOffset);

double _mean(List<double> values) =>
    values.fold<double>(0, (a, b) => a + b) / values.length;

double? _round1(double? v) => v == null ? null : (v * 10).round() / 10;
