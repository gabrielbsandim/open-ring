import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/goals/application/goal_reviewer.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/today/application/readiness_trend.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

void expectSameGoal(Goal? actual, Goal expected) {
  expect(actual, isNotNull);
  final goal = actual!;
  expect(goal.id, expected.id);
  expect(goal.kind, expected.kind);
  expect(goal.pace, expected.pace);
  expect(goal.startedOn, expected.startedOn);
  expect(goal.anchorKg, expected.anchorKg);
  expect(goal.referenceKg, expected.referenceKg);
  expect(goal.blockStartedOn, expected.blockStartedOn);
  expect(goal.blockAnchorKg, expected.blockAnchorKg);
  expect(goal.phase, expected.phase);
  expect(goal.phaseSince, expected.phaseSince);
  expect(goal.phaseUntil, expected.phaseUntil);
  expectSameLevers(goal.levers, expected.levers);
  expect(goal.endedOn, expected.endedOn);
  expect(goal.endReason, expected.endReason);
}

void expectSameLevers(List<Lever> actual, List<Lever> expected) {
  expect(
    [for (final lever in actual) (lever.kind, lever.target)],
    [for (final lever in expected) (lever.kind, lever.target)],
  );
}

void expectSameChange(LeverChange? actual, LeverChange? expected) {
  expect(actual == null, expected == null);
  if (actual == null || expected == null) return;
  expect(actual.kind, expected.kind);
  expect(actual.from, expected.from);
  expect(actual.to, expected.to);
}

void expectSameInputs(ReviewInputs actual, ReviewInputs expected) {
  expect(actual.kind, expected.kind);
  expect(actual.week, expected.week);
  expect(actual.levers.length, expected.levers.length);
  for (var i = 0; i < expected.levers.length; i++) {
    expect(actual.levers[i].lever.kind, expected.levers[i].lever.kind);
    expect(actual.levers[i].lever.target, expected.levers[i].lever.target);
    expect(actual.levers[i].achieved, expected.levers[i].achieved);
  }
  expect(actual.adherencePrevious, expected.adherencePrevious);
  expect(actual.baseline.stepsMedian14, expected.baseline.stepsMedian14);
  expect(actual.baseline.bedMedian, expected.baseline.bedMedian);
  expect(actual.baseline.wakeMedian, expected.baseline.wakeMedian);
  expect(actual.baseline.effortMean4Weeks, expected.baseline.effortMean4Weeks);
  expect(
    actual.baseline.strengthDaysUsual,
    expected.baseline.strengthDaysUsual,
  );
  expect(actual.effortRaisesInRow, expected.effortRaisesInRow);
  expect(actual.rate == null, expected.rate == null);
  expect(actual.rate?.kg, expected.rate?.kg);
  expect(actual.rate?.kgLow, expected.rate?.kgLow);
  expect(actual.rate?.kgHigh, expected.rate?.kgHigh);
  expect(actual.rate?.percent, expected.rate?.percent);
  expect(actual.rate?.percentLow, expected.rate?.percentLow);
  expect(actual.rate?.percentHigh, expected.rate?.percentHigh);
  expect(actual.targetPercent, expected.targetPercent);
  expect(actual.capPercent, expected.capPercent);
  expect(actual.previousPercentLow, expected.previousPercentLow);
  expect(actual.bmi, expected.bmi);
  expect(actual.pregnantOrBreastfeeding, expected.pregnantOrBreastfeeding);
  expect(actual.screeningPositive, expected.screeningPositive);
  expect(actual.bodyOn, expected.bodyOn);
  expect(actual.readiness, expected.readiness);
  expect(actual.recoveryPrevious, expected.recoveryPrevious);
  expect(actual.energy, expected.energy);
  expect(actual.energyPrevious, expected.energyPrevious);
  expect(actual.foodOrWeight, expected.foodOrWeight);
  expect(actual.foodOrWeightPrevious, expected.foodOrWeightPrevious);
}

const strengthLever = Lever(kind: LeverKind.strengthDays, target: 2);
const sleepLever = Lever(kind: LeverKind.sleepWindow, target: 690);
const stepsLever = Lever(kind: LeverKind.steps, target: 9000);

const f1 = ReviewInputs(
  kind: GoalKind.loseFat,
  week: 3,
  levers: [
    LeverWeek(lever: strengthLever, achieved: 2),
    LeverWeek(lever: sleepLever, achieved: 6),
    LeverWeek(lever: stepsLever, achieved: 5),
  ],
  adherencePrevious: 1,
  baseline: LeverBaseline(
    stepsMedian14: 8000,
    bedMedian: 705,
    wakeMedian: 405,
    effortMean4Weeks: null,
    strengthDaysUsual: 1,
  ),
  effortRaisesInRow: 0,
  rate: LossRate(
    kg: 0.2958,
    kgLow: 0.2034,
    kgHigh: 0.3881,
    percent: 0.380,
    percentLow: 0.261,
    percentHigh: 0.499,
  ),
  targetPercent: 0.5,
  capPercent: 0.5,
  previousPercentLow: 0.3,
  bmi: 24.55,
  pregnantOrBreastfeeding: false,
  screeningPositive: false,
  bodyOn: true,
  readiness: [76, 72, 70, 68, 74, 71, 76],
  recoveryPrevious: false,
  energy: CheckInEnergy.good,
  energyPrevious: CheckInEnergy.normal,
  foodOrWeight: false,
  foodOrWeightPrevious: false,
);

const f0 = ReviewInputs(
  kind: GoalKind.sleepBetter,
  week: 1,
  levers: [],
  adherencePrevious: null,
  baseline: LeverBaseline(
    stepsMedian14: null,
    bedMedian: null,
    wakeMedian: null,
    effortMean4Weeks: null,
    strengthDaysUsual: 0,
  ),
  effortRaisesInRow: 0,
  rate: null,
  targetPercent: 0.5,
  capPercent: 0.5,
  previousPercentLow: null,
  bmi: null,
  pregnantOrBreastfeeding: false,
  screeningPositive: false,
  bodyOn: false,
  readiness: [null, null, null, null, null, null, null],
  recoveryPrevious: false,
  energy: null,
  energyPrevious: null,
  foodOrWeight: null,
  foodOrWeightPrevious: null,
);

ReviewInputs f1With({
  required CheckInEnergy? energy,
  required CheckInEnergy? energyPrevious,
  required bool? foodOrWeight,
}) => ReviewInputs(
  kind: f1.kind,
  week: f1.week,
  levers: f1.levers,
  adherencePrevious: f1.adherencePrevious,
  baseline: f1.baseline,
  effortRaisesInRow: f1.effortRaisesInRow,
  rate: f1.rate,
  targetPercent: f1.targetPercent,
  capPercent: f1.capPercent,
  previousPercentLow: f1.previousPercentLow,
  bmi: f1.bmi,
  pregnantOrBreastfeeding: f1.pregnantOrBreastfeeding,
  screeningPositive: f1.screeningPositive,
  bodyOn: f1.bodyOn,
  readiness: f1.readiness,
  recoveryPrevious: f1.recoveryPrevious,
  energy: energy,
  energyPrevious: energyPrevious,
  foodOrWeight: foodOrWeight,
  foodOrWeightPrevious: f1.foodOrWeightPrevious,
);

ReviewInputs f1WithBmi(double bmi) => ReviewInputs(
  kind: f1.kind,
  week: f1.week,
  levers: f1.levers,
  adherencePrevious: f1.adherencePrevious,
  baseline: f1.baseline,
  effortRaisesInRow: f1.effortRaisesInRow,
  rate: f1.rate,
  targetPercent: f1.targetPercent,
  capPercent: f1.capPercent,
  previousPercentLow: f1.previousPercentLow,
  bmi: bmi,
  pregnantOrBreastfeeding: f1.pregnantOrBreastfeeding,
  screeningPositive: f1.screeningPositive,
  bodyOn: f1.bodyOn,
  readiness: f1.readiness,
  recoveryPrevious: f1.recoveryPrevious,
  energy: f1.energy,
  energyPrevious: f1.energyPrevious,
  foodOrWeight: f1.foodOrWeight,
  foodOrWeightPrevious: f1.foodOrWeightPrevious,
);

// Four of the seven values are under the fair band, which is rule 4.
ReviewInputs f1Recovering({
  required bool recoveryPrevious,
  CheckInEnergy? energy = CheckInEnergy.good,
  CheckInEnergy? energyPrevious = CheckInEnergy.normal,
  bool? foodOrWeight = false,
}) => ReviewInputs(
  kind: f1.kind,
  week: f1.week,
  levers: f1.levers,
  adherencePrevious: f1.adherencePrevious,
  baseline: f1.baseline,
  effortRaisesInRow: f1.effortRaisesInRow,
  rate: f1.rate,
  targetPercent: f1.targetPercent,
  capPercent: f1.capPercent,
  previousPercentLow: f1.previousPercentLow,
  bmi: f1.bmi,
  pregnantOrBreastfeeding: f1.pregnantOrBreastfeeding,
  screeningPositive: f1.screeningPositive,
  bodyOn: f1.bodyOn,
  readiness: [52, 49, 58, 54, 61, 50, 66],
  recoveryPrevious: recoveryPrevious,
  energy: energy,
  energyPrevious: energyPrevious,
  foodOrWeight: foodOrWeight,
  foodOrWeightPrevious: f1.foodOrWeightPrevious,
);

const Set<ModuleId> goalModules = {ModuleId.goals, ModuleId.body};
const closedWeekReadiness = [76, 72, 70, 68, 74, 71, 76];
const otherDayReadiness = 40;

LocalDate goalDay(int month, int day) => LocalDate(2026, month, day);

DateTime goalAt(int month, int day, [int hour = 8, int minute = 10]) =>
    DateTime(2026, month, day, hour, minute);

DateTime goalUtc(LocalDate date, int minuteOfDay) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).add(Duration(minutes: minuteOfDay));

SleepNight goalNight(LocalDate date, {required int onset, required int wake}) {
  final onsetDate = onset >= 720 ? date.addDays(-1) : date;
  return SleepNight([
    SleepSpan(
      start: goalUtc(onsetDate, onset),
      end: goalUtc(date, wake),
      phase: SleepPhase.light,
      utcOffset: Duration.zero,
    ),
  ]);
}

DailyActivity goalActivity(LocalDate date, int steps) => DailyActivity(
  date: date,
  steps: steps,
  activeKilocalories: 0,
  distanceMeters: 0,
);

EffortSession goalSession(LocalDate date) => (
  date: date,
  start: goalUtc(date, 480),
  end: goalUtc(date, 540),
  elapsed: const Duration(hours: 1),
  type: WorkoutType.strength,
  points: IntensityMinutes.none,
  load: const SessionLoad(
    byHeartRate: null,
    byRating: null,
    byDefault: 150,
    value: 150,
    source: LoadSource.typeDefault,
  ),
  rating: null,
  strength: true,
);

// The closed week is that of case 13 of the review inputs; the other days are
// chosen so the baseline medians are 8000, 705, 405 and a usual 1 strength day.
Map<LocalDate, DailyActivity> goalStepDays() => {
  for (var d = 23; d <= 29; d++)
    goalDay(11, d): goalActivity(goalDay(11, d), 7500),
  for (final (date, steps) in [
    (goalDay(11, 30), 9000),
    (goalDay(12, 1), 9500),
    (goalDay(12, 2), 10000),
    (goalDay(12, 3), 9100),
    (goalDay(12, 4), 12000),
    (goalDay(12, 5), 8500),
    (goalDay(12, 6), 8999),
    (goalDay(12, 7), 20000),
  ])
    date: goalActivity(date, steps),
};

Map<LocalDate, SleepNight> goalNights() => {
  for (var d = 23; d <= 29; d++)
    goalDay(11, d): goalNight(goalDay(11, d), onset: 23 * 60 + 45, wake: 405),
  for (var d = 1; d <= 7; d++)
    goalDay(12, d): goalNight(goalDay(12, d), onset: 23 * 60 + 30, wake: 420),
};

List<EffortSession> goalSessions() => [
  goalSession(goalDay(11, 20)),
  goalSession(goalDay(11, 25)),
  goalSession(goalDay(11, 30)),
  goalSession(goalDay(12, 5)),
];

List<DailyValue> goalWeights() => [
  for (var i = 0; i < 28; i++)
    (date: goalDay(11, 9).addDays(i), value: 80.0 - 0.05 * i),
];

WeightSummary goalWeightSummary({int extraDays = 0, List<DailyValue>? days}) {
  final later = [
    for (var i = 1; i <= extraDays; i++)
      (date: goalDay(12, 6).addDays(i), value: 70.0),
  ];
  return WeightSummary(
    last: WeighIn(
      id: 1,
      at: DateTime.utc(2026, 12, 6, 7),
      offsetMinutes: 0,
      kilograms: 78,
      source: WeighInSource.manual,
    ),
    daily: [...(days ?? goalWeights()), ...later],
    line: [
      (date: goalDay(12, 5), value: 78.1),
      (date: goalDay(12, 6), value: 78.0),
      ...later,
    ],
    rate: const WeightRateBuilding(daysMissing: 1, spanMissing: 1),
    noise: 0.5,
  );
}

ReadinessTrend goalReadiness(LocalDate today, LocalDate monday) {
  final firstClosed = monday.addDays(-7);
  return ReadinessTrend(
    today: today,
    values: [
      for (var age = 13; age >= 0; age--)
        goalReadinessOn(today.addDays(-age), firstClosed),
    ],
  );
}

int goalReadinessOn(LocalDate date, LocalDate firstClosed) {
  final index = date.daysSince(firstClosed);
  if (index < 0 || index > 6) return otherDayReadiness;
  return closedWeekReadiness[index];
}

GoalDraft goalDraft({
  GoalKind kind = GoalKind.loseFat,
  LocalDate startedOn = const LocalDate(2026, 11, 16),
  List<Lever> levers = const [strengthLever, sleepLever, stepsLever],
}) => GoalDraft(
  kind: kind,
  pace: kind == GoalKind.loseFat ? GoalPace.standard : null,
  startedOn: startedOn,
  anchorKg: kind == GoalKind.loseFat ? 78 : null,
  referenceKg: kind == GoalKind.loseFat ? 70 : null,
  levers: levers,
);

final class UnreadableGoalStore implements GoalStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('the store was read: ${invocation.memberName}');
}

final class GoalSetup {
  new(this.container, this.store);

  final ProviderContainer container;
  final InMemoryGoalStore store;

  GoalReviewer get reviewer => container.read(goalReviewerProvider.notifier);

  int get revision => container.read(dataRevisionProvider);

  Future<List<GoalWeek>> weeks() => store.weeks(1);
}

// clockOf replaces the fixed clock, extraOverrides adds providers a test needs
// and settleModules false leaves the module store unread on return.
Future<GoalSetup> setupGoals({
  DateTime? now,
  DateTime Function()? clockOf,
  Set<ModuleId> modules = goalModules,
  ModuleStore? moduleStore,
  bool settleModules = true,
  GoalDraft? draft,
  InMemoryGoalStore? store,
  GoalStore? readStore,
  Override? stepsOverride,
  Override? nightsOverride,
  Override? weightOverride,
  Override? profileOverride,
  List<Override> extraOverrides = const [],
  int extraWeighIns = 0,
}) async {
  final clock = now ?? goalAt(12, 7);
  final today = LocalDate(clock.year, clock.month, clock.day);
  final monday = mondayOf(today);
  final memory = store ?? InMemoryGoalStore();
  if (draft != null) await memory.start(draft);
  final container = ProviderContainer.test(
    overrides: [
      clockProvider.overrideWithValue(clockOf ?? () => clock),
      moduleStoreProvider.overrideWithValue(
        moduleStore ?? InMemoryModuleStore(modules),
      ),
      goalStoreProvider.overrideWithValue(readStore ?? memory),
      profileOverride ??
          userProfileStoreProvider.overrideWithValue(
            InMemoryUserProfileStore(const UserProfile(heightCentimeters: 178)),
          ),
      stepsOverride ??
          activityDaysProvider.overrideWith((ref) async => goalStepDays()),
      nightsOverride ??
          sleepNightsProvider.overrideWith((ref) async => goalNights()),
      effortSessionsProvider.overrideWith((ref) async => goalSessions()),
      dailyIntensityProvider.overrideWith((ref) async => <DailyValue>[]),
      readinessTrendProvider.overrideWith(
        (ref) async => goalReadiness(today, monday),
      ),
      weightOverride ??
          weightSummaryProvider.overrideWith(
            (ref) async => goalWeightSummary(extraDays: extraWeighIns),
          ),
      ...extraOverrides,
    ],
  );
  if (settleModules) await container.read(enabledModulesProvider.future);
  return GoalSetup(container, memory);
}
