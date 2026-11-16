import 'dart:math' as math;

const energyAdultAge = 18;
const energyRestingMargin = 0.10;
const energyDayMargin = 0.15;
const energyRangeStep = 50;
const energyBaseFactor = 1.3;
const energyWalkCostPerKgKm = 0.5;
const energyStepLengthFactor = 0.415;

// Mifflin and colleagues, 1990: kcal a day from kilograms, centimeters and
// years, plus a constant by sex.
const mifflinPerKilogram = 9.99;
const mifflinPerCentimeter = 6.25;
const mifflinPerYear = 4.92;
const mifflinMaleOffset = 5.0;
const mifflinFemaleOffset = -161.0;

enum EnergySex { female, male }

typedef EnergyRange = ({int low, int high});

/// The kcal a day an average adult of this size burns at rest, or null when a
/// field is missing or the person is under [energyAdultAge].
double? restingEnergy({
  required EnergySex? sex,
  required int? age,
  required double? kilograms,
  required double? centimeters,
}) {
  if (sex == null || age == null) return null;
  if (kilograms == null || centimeters == null) return null;
  if (age < energyAdultAge) return null;
  final offset = switch (sex) {
    EnergySex.male => mifflinMaleOffset,
    EnergySex.female => mifflinFemaleOffset,
  };
  return mifflinPerKilogram * kilograms +
      mifflinPerCentimeter * centimeters -
      mifflinPerYear * age +
      offset;
}

/// [value] less and plus [margin], each end rounded to [energyRangeStep].
EnergyRange energyRange(double value, double margin) =>
    (low: _stepped(value * (1 - margin)), high: _stepped(value * (1 + margin)));

int _stepped(double value) =>
    (value / energyRangeStep).round() * energyRangeStep;

/// The share of a day's base burn spent after [elapsed] of its 24 hours.
double baseEnergy(double resting, Duration elapsed) =>
    resting *
    energyBaseFactor *
    math.max(elapsed.inMicroseconds, 0) /
    Duration.microsecondsPerDay;

/// The kcal above rest of walking [steps], with the step length taken from
/// the height.
double stepEnergy({
  required int steps,
  required double kilograms,
  required double centimeters,
}) {
  final kilometers = steps * energyStepLengthFactor * centimeters / 100000;
  return energyWalkCostPerKgKm * kilograms * kilometers;
}

/// The kcal above rest of [elapsed] at an intensity of [met].
double workoutEnergy({
  required double met,
  required double kilograms,
  required Duration elapsed,
}) =>
    math.max(met - 1, 0) *
    kilograms *
    elapsed.inMicroseconds /
    Duration.microsecondsPerHour;
