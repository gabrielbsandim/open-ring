import 'package:metrics/src/score.dart';

typedef Part<F extends Enum> = ({
  F factor,
  double baseWeight,
  double value,
  double subscore,
});

double ramp(double x, {required double zeroAt, required double fullAt}) =>
    ((x - zeroAt) / (fullAt - zeroAt)).clamp(0.0, 1.0);

Scored<F> weigh<F extends Enum>(List<Part<F>> parts) {
  final available = parts.fold<double>(0, (sum, p) => sum + p.baseWeight);
  return Scored([
    for (final p in parts)
      Contribution(
        factor: p.factor,
        value: p.value,
        subscore: p.subscore,
        weight: p.baseWeight * 100 / available,
      ),
  ]);
}
