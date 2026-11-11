import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';

typedef TrendPoint = ({LocalDate date, double? value});

typedef TrendBand = ({double low, double high});

const trendMinHalfValues = 2;

@immutable
final class TrendSeries {
  new _({
    required List<TrendPoint> points,
    required this.partialLast,
    required this.mean,
    required this.min,
    required this.max,
    required this.measuredDays,
    required this.change,
    required List<double> settled,
  }) : points = List.unmodifiable(points),
       _settled = List.unmodifiable(settled);

  factory of(
    Iterable<DailyValue> values, {
    required LocalDate today,
    required int days,
    bool partialLast = false,
  }) {
    if (days < 1) {
      throw ArgumentError.value(days, 'days', 'must be at least 1');
    }
    final byDate = <LocalDate, List<double>>{};
    for (final v in values) {
      final age = today.daysSince(v.date);
      if (age < 0 || age >= days || !v.value.isFinite) continue;
      byDate.putIfAbsent(v.date, () => []).add(v.value);
    }
    final first = today.addDays(1 - days);
    final points = [
      for (var i = 0; i < days; i++)
        (date: first.addDays(i), value: _mean(byDate[first.addDays(i)])),
    ];
    final candidates = partialLast
        ? points.sublist(0, points.length - 1)
        : points;
    final settled = _present(candidates);
    return TrendSeries._(
      points: points,
      partialLast: partialLast,
      mean: _mean(settled),
      min: settled.isEmpty ? null : settled.reduce((a, b) => a < b ? a : b),
      max: settled.isEmpty ? null : settled.reduce((a, b) => a > b ? a : b),
      measuredDays: settled.length,
      change: _halfChange(candidates),
      settled: settled,
    );
  }

  final List<TrendPoint> points;
  final bool partialLast;
  final double? mean;
  final double? min;
  final double? max;
  final int measuredDays;
  final double? change;
  final List<double> _settled;

  int get days => points.length;

  LocalDate get firstDate => points.first.date;

  double? get latest => points.last.value;

  bool get hasStats => mean != null;

  int inside(TrendBand band) =>
      _settled.where((v) => v >= band.low && v <= band.high).length;

  // Second half minus first half, each half needing a couple of values so a
  // single stray day cannot set the direction.
  static double? _halfChange(List<TrendPoint> points) {
    final half = points.length ~/ 2;
    final early = _present(points.sublist(0, half));
    final recent = _present(points.sublist(half));
    if (early.length < trendMinHalfValues ||
        recent.length < trendMinHalfValues) {
      return null;
    }
    return _mean(recent)! - _mean(early)!;
  }

  static List<double> _present(Iterable<TrendPoint> points) => [
    for (final p in points) ?p.value,
  ];

  static double? _mean(List<double>? values) {
    if (values == null || values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }
}
