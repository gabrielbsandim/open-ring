final class Contribution<F extends Enum> {
  const new({
    required this.factor,
    required this.value,
    required this.subscore,
    required this.weight,
  });

  final F factor;
  final double value;
  final double subscore;
  final double weight;

  double get points => subscore * weight;
}

sealed class ScoreResult<F extends Enum> {
  const new();
}

final class Scored<F extends Enum> extends ScoreResult<F> {
  new(List<Contribution<F>> contributions)
    : contributions = List.unmodifiable(contributions);

  final List<Contribution<F>> contributions;

  double get total => contributions.fold(0, (sum, c) => sum + c.points);

  int get value => total.round().clamp(0, 100);

  Contribution<F>? of(F factor) {
    for (final c in contributions) {
      if (c.factor == factor) return c;
    }
    return null;
  }
}

final class InsufficientData<F extends Enum> extends ScoreResult<F> {
  new(List<F> missing) : missing = List.unmodifiable(missing);

  final List<F> missing;
}
