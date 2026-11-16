import 'package:metrics/metrics.dart';
import 'package:open_ring/features/open_score/domain/overall_history.dart';

const overallFloorPercentile = 10;
const overallTrendMinWeeks = 2;

// comparable: scored on the same factors as the latest scored week.
typedef OverallPoint = ({LocalDate date, int? score, bool comparable});

typedef OverallFactorChange = ({OverallFactor factor, double points});

final class OverallTrend {
  new({
    required Iterable<OverallPoint> points,
    required this.since,
    required this.typical,
    required this.floor,
    required Iterable<OverallFactorChange> changes,
  }) : points = List.unmodifiable(points),
       changes = List.unmodifiable(changes);

  // Null while fewer than two Mondays have a score.
  static OverallTrend? of(List<OverallWeek> weeks) {
    final scored = [
      for (final week in weeks)
        if (week.result case final Scored<OverallFactor> result)
          (week: week, result: result),
    ];
    if (scored.length < overallTrendMinWeeks) return null;
    final values = [for (final entry in scored) entry.result.value]..sort();
    final first = scored.first;
    final last = scored.last;
    final parts = _factors(last.week.inputs);
    final before = {
      for (final c in first.week.inputs.contributions) c.factor: c.points,
    };
    return OverallTrend(
      points: [
        for (final week in weeks)
          (
            date: week.date,
            score: switch (week.result) {
              final Scored<OverallFactor> result => result.value,
              InsufficientData() => null,
            },
            comparable: _same(_factors(week.inputs), parts),
          ),
      ],
      since: (
        date: first.week.date,
        change: last.result.value - first.result.value,
      ),
      typical: _median(values),
      floor: values[(values.length * overallFloorPercentile / 100).ceil() - 1],
      changes: [
        for (final c in last.week.inputs.contributions)
          if (before[c.factor] case final earlier?)
            (factor: c.factor, points: c.points - earlier),
      ],
    );
  }

  final List<OverallPoint> points;
  final ({LocalDate date, int change}) since;
  final int typical;
  final int floor;

  // Points earned now against the first scored week, for factors in both.
  final List<OverallFactorChange> changes;

  int get now => points.lastWhere((point) => point.score != null).score!;
}

int _median(List<int> sorted) {
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return ((sorted[middle - 1] + sorted[middle]) / 2).round();
}

Set<OverallFactor> _factors(OverallInputs inputs) => {
  for (final c in inputs.contributions) c.factor,
};

bool _same(Set<OverallFactor> a, Set<OverallFactor> b) =>
    a.length == b.length && a.containsAll(b);
