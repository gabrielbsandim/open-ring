import 'dart:math' as math;

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

// One day's math on the published scale, whether or not the day has a score.
final class DayScoreReceipt {
  new(this.inputs)
    : result = inputs.score,
      _parts = {for (final part in inputs.contributions) part.factor: part};

  final DayScoreInputs inputs;
  final ScoreResult<DayScoreFactor> result;
  final Map<DayScoreFactor, Contribution<DayScoreFactor>> _parts;

  Contribution<DayScoreFactor>? of(DayScoreFactor factor) => _parts[factor];

  Scored<DayScoreFactor>? get scored => switch (result) {
    final Scored<DayScoreFactor> scored => scored,
    InsufficientData<DayScoreFactor>() => null,
  };

  DayScoreGap? get gap => switch (result) {
    final InsufficientData<DayScoreFactor> lacking => lacking.gap,
    Scored<DayScoreFactor>() => null,
  };

  List<DayScoreFactor> get missing => [
    for (final factor in DayScoreFactor.values)
      if (!_parts.containsKey(factor)) factor,
  ];

  double earned(Iterable<DayScoreFactor> factors) =>
      factors.fold(0, (sum, factor) => sum + (_parts[factor]?.points ?? 0));

  double available(Iterable<DayScoreFactor> factors) =>
      _weights(factors.where(_parts.containsKey));

  double get total => earned(DayScoreFactor.values);

  double get coverage => available(DayScoreFactor.values);

  double get open =>
      available(dayScoreOpenFactors) - earned(dayScoreOpenFactors);

  // The fewest decimals of the earned points that still rescale to the score,
  // so a reader who redoes the division lands on the number shown.
  int get rescaleDigits {
    final value = scored?.value;
    if (value == null) return 1;
    for (var digits = 1; digits < _maxRescaleDigits; digits++) {
      final scale = math.pow(10, digits);
      final shown = (total * scale).round() / scale;
      if ((shown / coverage * 100).round() == value) return digits;
    }
    return _maxRescaleDigits;
  }
}

const _maxRescaleDigits = 6;
