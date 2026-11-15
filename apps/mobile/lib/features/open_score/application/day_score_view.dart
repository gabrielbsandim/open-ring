import 'package:metrics/metrics.dart';

enum DayScoreGap { night, steps, coverage }

const List<DayScoreFactor> dayScoreOpenFactors = [
  DayScoreFactor.steps,
  DayScoreFactor.intensity,
];

double _weights(Iterable<DayScoreFactor> factors) =>
    factors.fold(0, (sum, factor) => sum + factor.weight);

Iterable<DayScoreFactor> factorsOf(DayScorePillar pillar) =>
    DayScoreFactor.values.where((factor) => factor.pillar == pillar);

extension DayScoreMissing on InsufficientData<DayScoreFactor> {
  double get coverage => dayScoreFullCoverage - _weights(missing);

  bool has(DayScoreFactor factor) => !missing.contains(factor);

  DayScoreGap get gap {
    if (!has(DayScoreFactor.sleep)) return DayScoreGap.night;
    if (!has(DayScoreFactor.steps)) return DayScoreGap.steps;
    return DayScoreGap.coverage;
  }
}

// Points on the published scale, before the rescale that coverage applies.
extension DayScorePoints on Scored<DayScoreFactor> {
  double earned(Iterable<DayScoreFactor> factors) => factors.fold(
    0,
    (sum, factor) => sum + factor.weight * (of(factor)?.subscore ?? 0),
  );

  double available(Iterable<DayScoreFactor> factors) =>
      _weights(factors.where((factor) => of(factor) != null));

  double get open =>
      available(dayScoreOpenFactors) - earned(dayScoreOpenFactors);
}
