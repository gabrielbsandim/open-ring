import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/goal.dart';

const _daysInWeek = 7;
const _noBmiCapPercent = 0.5;

/// What a review carries over from the weeks reviewed before it.
final class ReviewHistory {
  const new({
    required this.adherencePrevious,
    required this.previousPercentLow,
    required this.recoveryPrevious,
    required this.effortRaisesInRow,
    required this.energyPrevious,
    required this.foodOrWeightPrevious,
  });

  final double? adherencePrevious;
  final double? previousPercentLow;
  final bool recoveryPrevious;
  final int effortRaisesInRow;
  final CheckInEnergy? energyPrevious;
  final bool? foodOrWeightPrevious;
}

typedef ScreeningFlags = ({
  bool pregnantOrBreastfeeding,
  bool screeningPositive,
});

typedef WeightReading = ({
  LossRate? rate,
  double targetPercent,
  double capPercent,
  double? bmi,
});

typedef WeightSnapshot = ({WeightRate? rate, double? trendKg});

/// The weight as it stood on [asOf]: later weigh-ins are not read, and a
/// trend whose last point is a whole rate window old is no trend.
WeightSnapshot weightSnapshot({
  required List<DailyValue> daily,
  required List<DailyValue> line,
  required LocalDate asOf,
}) {
  final point = line
      .where((point) => point.date.compareTo(asOf) <= 0)
      .lastOrNull;
  final fresh =
      point != null && asOf.daysSince(point.date) < weightRateWindowDays;
  return (
    rate: daily.isEmpty ? null : weightRate(daily, today: asOf),
    trendKg: fresh ? point.value : null,
  );
}

ReviewInputs withCheckIn(
  ReviewInputs inputs, {
  required CheckInEnergy? energy,
  required bool? foodOrWeight,
}) => ReviewInputs(
  kind: inputs.kind,
  week: inputs.week,
  levers: inputs.levers,
  adherencePrevious: inputs.adherencePrevious,
  baseline: inputs.baseline,
  effortRaisesInRow: inputs.effortRaisesInRow,
  rate: inputs.rate,
  targetPercent: inputs.targetPercent,
  capPercent: inputs.capPercent,
  previousPercentLow: inputs.previousPercentLow,
  bmi: inputs.bmi,
  pregnantOrBreastfeeding: inputs.pregnantOrBreastfeeding,
  screeningPositive: inputs.screeningPositive,
  bodyOn: inputs.bodyOn,
  readiness: inputs.readiness,
  recoveryPrevious: inputs.recoveryPrevious,
  energy: energy,
  energyPrevious: inputs.energyPrevious,
  foodOrWeight: foodOrWeight,
  foodOrWeightPrevious: inputs.foodOrWeightPrevious,
);

// Only the week reviewed seven days before counts as the previous one: after
// a gap nothing is carried over.
ReviewHistory reviewHistory(List<GoalWeek> weeks, {required LocalDate monday}) {
  final byMonday = {for (final week in weeks) week.monday: week};
  final previous = byMonday[monday.addDays(-_daysInWeek)];
  return ReviewHistory(
    adherencePrevious: previous == null
        ? null
        : adherence(previous.inputs.levers),
    previousPercentLow: previous?.inputs.rate?.percentLow,
    recoveryPrevious: previous?.action == ReviewAction.recoveryWeek,
    effortRaisesInRow: _effortRaises(byMonday, monday),
    energyPrevious: previous?.inputs.energy,
    foodOrWeightPrevious: previous?.inputs.foodOrWeight,
  );
}

/// Each flag is its newest answer: a screening that did not ask a question
/// leaves the earlier answer standing.
ScreeningFlags screeningFlags(List<GoalScreening> newestFirst) => (
  pregnantOrBreastfeeding:
      newestFirst
          .map((screening) => screening.pregnantOrBreastfeeding)
          .nonNulls
          .firstOrNull ??
      false,
  screeningPositive:
      newestFirst.map((screening) => screening.softMode).nonNulls.firstOrNull ??
      false,
);

// With Body off the rate and the BMI stay empty even when weigh-ins are
// stored, so no weight rule can fire on a weight nobody is tracking.
WeightReading weightReading({
  required GoalKind kind,
  required GoalPace? pace,
  required bool bodyOn,
  required WeightRate? rate,
  required double? trendKg,
  required double? heightCm,
}) {
  if (kind != GoalKind.loseFat) {
    return (
      rate: null,
      targetPercent: goalPacePercent(GoalPace.standard),
      capPercent: _noBmiCapPercent,
      bmi: null,
    );
  }
  final trend = bodyOn ? _positive(trendKg) : null;
  final height = _positive(heightCm);
  final index = trend == null || height == null ? null : bmi(trend, height);
  return (
    rate: rate is WeightRateReady && trend != null
        ? lossRate(rate, trend)
        : null,
    targetPercent: goalPacePercent(pace ?? GoalPace.standard),
    capPercent: index == null ? _noBmiCapPercent : lossCapPercent(index),
    bmi: index,
  );
}

/// The inputs of the review of the week that closed the day before [monday].
ReviewInputs closedWeekInputs({
  required Goal goal,
  required LocalDate monday,
  required GoalWeekData data,
  required LeverBaseline baseline,
  required List<GoalWeek> weeks,
  required List<GoalScreening> screenings,
  required bool bodyOn,
  required WeightRate? rate,
  required double? trendKg,
  required double? heightCm,
  required List<int?> readiness,
  CheckInEnergy? energy,
  bool? foodOrWeight,
}) {
  if (mondayOf(monday) != monday) {
    throw ArgumentError.value(monday, 'monday', 'must be a Monday');
  }
  if (readiness.length != _daysInWeek) {
    throw ArgumentError.value(readiness, 'readiness', 'must hold seven days');
  }
  final history = reviewHistory(weeks, monday: monday);
  final flags = screeningFlags(screenings);
  final weight = weightReading(
    kind: goal.kind,
    pace: goal.pace,
    bodyOn: bodyOn,
    rate: rate,
    trendKg: trendKg,
    heightCm: heightCm,
  );
  final closedMonday = monday.addDays(-_daysInWeek);
  return ReviewInputs(
    kind: goal.kind,
    week: goalWeekNumber(start: goal.blockStartedOn, today: monday),
    levers: [
      for (final lever in goal.levers)
        leverProgress(lever, data, monday: closedMonday, today: monday).week,
    ],
    adherencePrevious: history.adherencePrevious,
    baseline: baseline,
    effortRaisesInRow: history.effortRaisesInRow,
    rate: weight.rate,
    targetPercent: weight.targetPercent,
    capPercent: weight.capPercent,
    previousPercentLow: history.previousPercentLow,
    bmi: weight.bmi,
    pregnantOrBreastfeeding: flags.pregnantOrBreastfeeding,
    screeningPositive: flags.screeningPositive,
    bodyOn: bodyOn,
    readiness: readiness,
    recoveryPrevious: history.recoveryPrevious,
    energy: energy,
    energyPrevious: history.energyPrevious,
    foodOrWeight: foodOrWeight,
    foodOrWeightPrevious: history.foodOrWeightPrevious,
  );
}

int _effortRaises(Map<LocalDate, GoalWeek> byMonday, LocalDate monday) {
  var raises = 0;
  var at = monday.addDays(-_daysInWeek);
  while (_raisedEffort(byMonday[at])) {
    raises += 1;
    at = at.addDays(-_daysInWeek);
  }
  return raises;
}

bool _raisedEffort(GoalWeek? week) {
  final change = week?.change;
  final from = change?.from;
  final to = change?.to;
  if (change == null || from == null || to == null) return false;
  return change.kind == LeverKind.effortPoints &&
      to > from &&
      week?.answer == WeekAnswer.accepted;
}

double? _positive(double? value) {
  if (value == null || !value.isFinite || value <= 0) return null;
  return value;
}
