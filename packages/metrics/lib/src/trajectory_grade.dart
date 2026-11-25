import 'package:metrics/src/baseline.dart';
import 'package:metrics/src/local_date.dart';
import 'package:metrics/src/trajectory.dart';
import 'package:metrics/src/weight_trend.dart';

enum ProjectionGrade { below, inside, above }

/// Where the trend landed 4 weeks after the [monday] a band was stored, or
/// null before that day or with no weigh-in by then.
({ProjectionGrade grade, double actualKg})? gradeProjection({
  required LocalDate monday,
  required double low,
  required double high,
  required LocalDate today,
  required Iterable<DailyValue> weighIns,
}) {
  final due = monday.addDays(trajectoryFirmDays);
  if (today.compareTo(due) < 0) return null;
  final trend = weightTrend([
    for (final weighIn in weighIns)
      if (weighIn.date.compareTo(due) <= 0) weighIn,
  ]);
  if (trend.isEmpty) return null;
  final actual = trend.last.value;
  final grade = switch (actual) {
    _ when actual < low => ProjectionGrade.below,
    _ when actual > high => ProjectionGrade.above,
    _ => ProjectionGrade.inside,
  };
  return (grade: grade, actualKg: actual);
}
