import 'dart:math' as math;

import 'package:metrics/src/energy.dart';
import 'package:metrics/src/trajectory.dart';

// Hall 2011: the burn falls by about 24 kcal a day for each kilogram lost.
const trajectoryKcalPerKgDay = 24.0;

// Paluch 2022, all cause mortality by steps a day, quartile medians against
// the lowest group.
const List<({int steps, double hazard})> paluchAnchors = [
  (steps: 3553, hazard: 1.0),
  (steps: 5801, hazard: 0.60),
  (steps: 7842, hazard: 0.55),
  (steps: 10901, hazard: 0.47),
];

enum CohortWords {
  aboutTheSame,
  slightlyLower,
  fifthToQuarterLower,
  muchLower;

  static CohortWords of(double percentLower) {
    if (percentLower < 5) return aboutTheSame;
    if (percentLower < 15) return slightlyLower;
    if (percentLower < 30) return fifthToQuarterLower;
    return muchLower;
  }
}

/// The cohort hazard at [steps] a day, log linear between the anchors and flat
/// outside them.
double paluchHazard(int steps) {
  final first = paluchAnchors.first;
  final last = paluchAnchors.last;
  if (steps <= first.steps) return first.hazard;
  if (steps >= last.steps) return last.hazard;
  final upper = paluchAnchors.indexWhere((anchor) => steps < anchor.steps);
  final from = paluchAnchors[upper - 1];
  final to = paluchAnchors[upper];
  final share = (steps - from.steps) / (to.steps - from.steps);
  final logHazard =
      math.log(from.hazard) +
      share * (math.log(to.hazard) - math.log(from.hazard));
  return math.exp(logHazard);
}

final class StepsWhatIf {
  const new({
    required this.toSteps,
    required this.kilometers,
    required this.kcalPerDay,
    required this.kgLess4,
    required this.kgLess12,
    required this.hazardFrom,
    required this.hazardTo,
  });

  final int toSteps;
  final double kilometers;
  final double kcalPerDay;
  final double kgLess4;
  final double kgLess12;
  final double hazardFrom;
  final double hazardTo;

  double get percentLower => (1 - hazardTo / hazardFrom) * 100;

  CohortWords get words => CohortWords.of(percentLower);

  bool get clamped => toSteps > paluchAnchors.last.steps;
}

/// What [extraSteps] a day above [typicalSteps] would change, in weight after
/// 4 and 12 weeks and in the cohort words.
StepsWhatIf stepsWhatIf({
  required int extraSteps,
  required int typicalSteps,
  required double kilograms,
  required double centimeters,
}) {
  if (extraSteps < 0) {
    throw ArgumentError.value(extraSteps, 'extraSteps', 'must not be negative');
  }
  if (typicalSteps < 0) {
    throw ArgumentError.value(
      typicalSteps,
      'typicalSteps',
      'must not be negative',
    );
  }
  if (kilograms < 0 || centimeters < 0) {
    throw ArgumentError('kilograms and centimeters must not be negative');
  }
  final kcal = stepEnergy(
    steps: extraSteps,
    kilograms: kilograms,
    centimeters: centimeters,
  );
  double kgLess(int days) =>
      kcal /
      trajectoryKcalPerKgDay *
      scenarioDays(days) /
      trajectoryAdaptationDays;
  final toSteps = typicalSteps + extraSteps;
  return StepsWhatIf(
    toSteps: toSteps,
    kilometers: stepKilometers(steps: extraSteps, centimeters: centimeters),
    kcalPerDay: kcal,
    kgLess4: kgLess(trajectoryFirmDays),
    kgLess12: kgLess(trajectoryBandDays),
    hazardFrom: paluchHazard(typicalSteps),
    hazardTo: paluchHazard(toSteps),
  );
}
