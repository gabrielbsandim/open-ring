import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

enum AiAnalysisKind {
  dailyReview('daily_review'),
  weeklyReview('weekly_review');

  new(this.wireName);
  final String wireName;
}

enum AiDetailLevel {
  minimal('minimal'),
  standard('standard'),
  full('full');

  new(this.wireName);
  final String wireName;
}

enum AiContextWindow {
  compact(
    maxDays: 7,
    maxWeeks: 4,
    maxWorkouts: 6,
    maxFacts: 40,
    targetTokens: 1800,
    hardCapTokens: 2200,
  ),
  standard(
    maxDays: 14,
    maxWeeks: 12,
    maxWorkouts: 20,
    maxFacts: 90,
    targetTokens: 3500,
    hardCapTokens: 4500,
  ),
  extended(
    maxDays: 28,
    maxWeeks: 26,
    maxWorkouts: 40,
    maxFacts: 140,
    targetTokens: 6500,
    hardCapTokens: 8000,
  );

  new({
    required this.maxDays,
    required this.maxWeeks,
    required this.maxWorkouts,
    required this.maxFacts,
    required this.targetTokens,
    required this.hardCapTokens,
  });

  final int maxDays;
  final int maxWeeks;
  final int maxWorkouts;
  final int maxFacts;
  final int targetTokens;
  final int hardCapTokens;
}

enum AiMetricFamily { sleep, heart, activity, oxygen, stress, body, overall }

enum AiTrendDirection { up, down, flat }

enum AiBiologicalSex { male, female, other }

enum AiSleepSource { ring, imported, none }

enum AiWeekday { mon, tue, wed, thu, fri, sat, sun }

enum AiGoalStatus { active, paused, maintenance }

enum AiDistanceUnit { km, mi }

enum AiWeightUnit { kg, lb }

enum AiTrendMetric {
  sleepMin('sleep_min', requiresRing: false, minimalAllowed: false),
  sleepScore('sleep_score', requiresRing: false, minimalAllowed: true),
  rhr('rhr', requiresRing: true, minimalAllowed: false),
  hrv('hrv', requiresRing: true, minimalAllowed: false),
  steps('steps', requiresRing: true, minimalAllowed: true),
  load('load', requiresRing: false, minimalAllowed: true),
  readiness('readiness', requiresRing: true, minimalAllowed: true),
  weight('weight', requiresRing: false, minimalAllowed: false);

  new(
    this.wireName, {
    required this.requiresRing,
    required this.minimalAllowed,
  });

  final String wireName;
  final bool requiresRing;
  final bool minimalAllowed;
}

enum AiEnergyFormula {
  mifflinStJeor1990('mifflin_st_jeor_1990');

  new(this.wireName);
  final String wireName;
}

enum AiFactUnit {
  score('score'),
  nights('nights'),
  bpm('bpm'),
  steps('steps'),
  ms('ms'),
  min('min'),
  kg('kg'),
  kcal('kcal'),
  km('km'),
  mi('mi'),
  lb('lb'),
  hours('hours'),
  days('days'),
  pct('pct'),
  kgPerWeek('kg/wk'),
  levers('levers');

  new(this.wireName);
  final String wireName;
}

const Set<String> aiAllowedReplyLanguages = {
  'de',
  'en',
  'es',
  'fr',
  'id',
  'it',
  'ja',
  'pt',
  'pt-BR',
  'pt-PT',
  'ru',
  'zh',
};

const Map<String, String> aiKnownSourceApps = {
  'com.google.android.apps.fitness': 'Google Fit',
  'com.google.android.apps.healthdata': 'Health Connect',
  'com.sec.android.app.shealth': 'Samsung Health',
  'com.garmin.android.apps.connectmobile': 'Garmin Connect',
  'com.fitbit.FitbitMobile': 'Fitbit',
  'com.ouraring.oura': 'Oura',
  'com.withings.wiscale2': 'Withings',
  'com.xiaomi.wearable': 'Mi Fitness',
  'com.mi.health': 'Mi Fitness',
  'com.huawei.health': 'Huawei Health',
  'com.urbandroid.sleep': 'Sleep as Android',
  'fi.polar.polarflow': 'Polar Flow',
  'com.suunto.android': 'Suunto',
  'com.whoop.android': 'WHOOP',
  'com.zepp.app': 'Zepp',
};

String sanitizeReplyLanguage(String raw) {
  final normalized = raw.trim().replaceAll('_', '-');
  return aiAllowedReplyLanguages.contains(normalized) ? normalized : 'en';
}

String sanitizeSourceApp(String? raw) =>
    aiKnownSourceApps[raw?.trim()] ?? 'other app';

String formatAgeBand(int age, {required int width}) {
  if (width <= 0) {
    throw ArgumentError.value(width, 'width', 'Must be positive');
  }
  final clamped = age < 0 ? 0 : age;
  final low = (clamped ~/ width) * width;
  return '$low-${low + width - 1}';
}

@immutable
final class AiClockTime {
  const new(this.hour, this.minute);

  final int hour;
  final int minute;

  String format({required bool round15}) {
    final total = hour.clamp(0, 23) * 60 + minute.clamp(0, 59);
    final adjusted = round15 ? ((total + 7) ~/ 15) * 15 % 1440 : total;
    final h = (adjusted ~/ 60).toString().padLeft(2, '0');
    final m = (adjusted % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}

@immutable
sealed class AiLeverTarget {
  const new();
}

@immutable
final class AiLeverIntTarget extends AiLeverTarget {
  const new(this.value);
  final int value;
}

@immutable
final class AiLeverTimeTarget extends AiLeverTarget {
  const new(this.time);
  final AiClockTime time;
}

@immutable
final class AiUnits {
  const new({this.distance = AiDistanceUnit.km, this.weight = AiWeightUnit.kg});

  final AiDistanceUnit distance;
  final AiWeightUnit weight;
}

@immutable
final class AiProfileInput {
  const new({this.age, this.sex, this.heightCm, this.maxHr, this.stepGoal});

  final int? age;
  final AiBiologicalSex? sex;
  final int? heightCm;
  final int? maxHr;
  final int? stepGoal;
}

@immutable
final class AiCoverageInput {
  const new({
    required this.hasRing,
    required this.sleepSource,
    required this.daysWithRingData,
    this.importedIncluded = false,
  });

  final bool hasRing;
  final AiSleepSource sleepSource;
  final int daysWithRingData;
  final bool importedIncluded;
}

@immutable
final class AiDayRow {
  const new({
    required this.date,
    required this.weekday,
    this.sleepMin,
    this.sleepScore,
    this.deepMin,
    this.remMin,
    this.awakeMin,
    this.bedtime,
    this.wake,
    this.rhr,
    this.hrv,
    this.stressAvg,
    this.spo2Avg,
    this.spo2Min,
    this.steps,
    this.activeKcal,
    this.load,
    this.readiness,
    this.weight,
  });

  final LocalDate date;
  final AiWeekday weekday;
  final int? sleepMin;
  final int? sleepScore;
  final int? deepMin;
  final int? remMin;
  final int? awakeMin;
  final AiClockTime? bedtime;
  final AiClockTime? wake;
  final double? rhr;
  final double? hrv;
  final double? stressAvg;
  final double? spo2Avg;
  final double? spo2Min;
  final int? steps;
  final int? activeKcal;
  final int? load;
  final int? readiness;
  final double? weight;
}

@immutable
final class AiBaselineEntry {
  const new({required this.value, required this.days});
  final double value;
  final int days;
}

@immutable
final class AiBaselinesInput {
  const new({this.rhr, this.hrv, this.sleepMin});
  final AiBaselineEntry? rhr;
  final AiBaselineEntry? hrv;
  final AiBaselineEntry? sleepMin;
}

@immutable
final class AiWeekRow {
  const new({
    this.sleepMinAvg,
    this.sleepScoreAvg,
    this.rhrAvg,
    this.hrvAvg,
    this.stepsAvg,
    this.loadSum,
    this.workouts,
    this.readinessAvg,
    this.weightAvg,
  });

  final double? sleepMinAvg;
  final double? sleepScoreAvg;
  final double? rhrAvg;
  final double? hrvAvg;
  final double? stepsAvg;
  final int? loadSum;
  final int? workouts;
  final double? readinessAvg;
  final double? weightAvg;
}

@immutable
final class AiTrendItem {
  const new({
    required this.id,
    required this.metric,
    required this.last28,
    required this.prev28,
    required this.dir,
    required this.n,
  });

  final String id;
  final AiTrendMetric metric;
  final double last28;
  final double prev28;
  final AiTrendDirection dir;
  final int n;
}

@immutable
final class AiWorkoutRow {
  const new({
    required this.id,
    required this.daysAgo,
    required this.date,
    required this.type,
    required this.minutes,
    this.avgHr,
    this.maxHr,
    this.zones,
    this.distanceKm,
    this.kcal,
    this.isImported = false,
    this.sourceApp,
  });

  final String id;
  final int daysAgo;
  final LocalDate date;
  final WorkoutType type;
  final int minutes;
  final int? avgHr;
  final int? maxHr;
  final List<int>? zones;
  final double? distanceKm;
  final int? kcal;
  final bool isImported;
  final String? sourceApp;
}

@immutable
final class AiWeighInsSummary {
  const new({
    required this.n30,
    required this.trendLast,
    required this.kgPerWeek,
    required this.kgPerWeekLow,
    required this.kgPerWeekHigh,
    required this.daysSinceLast,
  });

  final int n30;
  final double trendLast;
  final double kgPerWeek;
  final double kgPerWeekLow;
  final double kgPerWeekHigh;
  final int daysSinceLast;
}

@immutable
final class AiEnergySummary {
  const new({
    required this.bmrKcal,
    required this.tdeeKcalAvg7,
    this.formula = AiEnergyFormula.mifflinStJeor1990,
  });

  final int bmrKcal;
  final int tdeeKcalAvg7;
  final AiEnergyFormula formula;
}

@immutable
final class AiGoalSummary {
  const new({
    required this.kind,
    required this.status,
    required this.startedDaysAgo,
    required this.startedDate,
    required this.blockWeek,
    required this.blockWeeks,
    this.rateTargetPct,
  });

  final GoalKind kind;
  final AiGoalStatus status;
  final int startedDaysAgo;
  final LocalDate startedDate;
  final int blockWeek;
  final int blockWeeks;
  final double? rateTargetPct;
}

@immutable
final class AiPlanLever {
  const new({
    required this.id,
    required this.kind,
    required this.target,
    required this.met,
    required this.isDaily,
  });

  final String id;
  final LeverKind kind;
  final AiLeverTarget target;
  final int met;
  final bool isDaily;
}

@immutable
final class AiFoodSummary {
  const new({
    required this.completeDays,
    this.plateScore,
    this.windowMedianMin,
    this.lastMealToSleepMin,
  });

  final int completeDays;
  final double? plateScore;
  final int? windowMedianMin;
  final int? lastMealToSleepMin;
}

@immutable
final class HealthFact {
  const new({
    required this.id,
    required this.label,
    required this.value,
    required this.unit,
    required this.family,
    required this.days,
    this.requiresRing = false,
    this.minimalAllowed = false,
    this.isWorkoutFact = false,
  });

  final String id;
  final String label;
  final double value;
  final AiFactUnit unit;
  final AiMetricFamily family;
  final int days;
  final bool requiresRing;
  final bool minimalAllowed;
  final bool isWorkoutFact;
}

@immutable
final class HealthContextInput {
  const new({
    required this.kind,
    required this.replyLanguage,
    required this.detail,
    required this.window,
    required this.units,
    required this.profile,
    required this.coverage,
    required this.days,
    this.baselines,
    this.weeks = const [],
    this.trends = const [],
    this.workouts = const [],
    this.weighIns,
    this.energy,
    this.goal,
    this.levers = const [],
    this.food,
    this.facts = const [],
  });

  final AiAnalysisKind kind;
  final String replyLanguage;
  final AiDetailLevel detail;
  final AiContextWindow window;
  final AiUnits units;
  final AiProfileInput profile;
  final AiCoverageInput coverage;
  final List<AiDayRow> days;
  final AiBaselinesInput? baselines;
  final List<AiWeekRow> weeks;
  final List<AiTrendItem> trends;
  final List<AiWorkoutRow> workouts;
  final AiWeighInsSummary? weighIns;
  final AiEnergySummary? energy;
  final AiGoalSummary? goal;
  final List<AiPlanLever> levers;
  final AiFoodSummary? food;
  final List<HealthFact> facts;
}

@immutable
final class BuiltAiPayload {
  const new({
    required this.contextMap,
    required this.canonicalContextJson,
    required this.systemPrompt,
    required this.userMessage,
    required this.facts,
    required this.estimatedTokens,
    required this.contextTokens,
    required this.cacheKey,
    required this.droppedCount,
  });

  final Map<String, Object?> contextMap;
  final String canonicalContextJson;
  final String systemPrompt;
  final String userMessage;
  final List<HealthFact> facts;
  final int estimatedTokens;
  final int contextTokens;
  final String cacheKey;
  final int droppedCount;
}
