import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/open_score/domain/overall_history.dart';
import 'package:open_ring/features/open_score/domain/overall_trend.dart';

const monday = LocalDate(2026, 11, 9);

OverallInputs inputs(double resting, {double? waist}) => OverallInputs(
  restingHeartRate: resting,
  sleepHours: 6.5,
  sleepRegularity: 70,
  weeklyMinutes: 150,
  dailySteps: 7000,
  waistToHeight: waist,
);

OverallWeek week(int back, OverallInputs? of) {
  final value = of ?? const OverallInputs();
  return (date: monday.addDays(-7 * back), inputs: value, result: value.score);
}

int scoreOf(OverallInputs value) =>
    (value.score as Scored<OverallFactor>).value;

void main() {
  test('fewer than two scored Mondays give no trend', () {
    expect(OverallTrend.of([week(1, null), week(0, inputs(60))]), isNull);
    expect(OverallTrend.of([]), isNull);
  });

  test('a week without a score is a gap and keeps its date', () {
    final trend = OverallTrend.of([
      week(2, inputs(70)),
      week(1, null),
      week(0, inputs(60)),
    ])!;

    expect(trend.points, hasLength(3));
    expect(trend.points[1].score, isNull);
    expect(trend.points[1].date, monday.addDays(-7));
    expect(trend.now, scoreOf(inputs(60)));
  });

  test('since compares now with the first scored week', () {
    final trend = OverallTrend.of([
      week(3, null),
      week(2, inputs(75)),
      week(1, inputs(65)),
      week(0, inputs(55)),
    ])!;

    expect(trend.since.date, monday.addDays(-14));
    expect(trend.since.change, scoreOf(inputs(55)) - scoreOf(inputs(75)));
    expect(trend.since.change, greaterThan(0));
  });

  test('typical is the median and the floor the 10th percentile', () {
    final resting = <double>[80, 78, 76, 74, 72, 70, 68, 66, 64, 62, 60, 58];
    final weeks = [
      for (var i = 0; i < resting.length; i++) week(11 - i, inputs(resting[i])),
    ];
    final sorted = [for (final value in resting) scoreOf(inputs(value))]
      ..sort();
    final trend = OverallTrend.of(weeks)!;

    expect(trend.floor, sorted[1]);
    expect(trend.typical, ((sorted[5] + sorted[6]) / 2).round());
  });

  test('with few weeks the floor is the lowest one', () {
    final trend = OverallTrend.of([
      week(2, inputs(60)),
      week(1, inputs(80)),
      week(0, inputs(70)),
    ])!;

    expect(trend.floor, scoreOf(inputs(80)));
    expect(trend.typical, scoreOf(inputs(70)));
  });

  test('a point is comparable when it used the factors of the last week', () {
    final trend = OverallTrend.of([
      week(2, inputs(60)),
      week(1, inputs(60, waist: 0.48)),
      week(0, inputs(62, waist: 0.48)),
    ])!;

    expect(
      [for (final point in trend.points) point.comparable],
      [false, true, true],
    );
  });

  test('an early first score after the last Monday is the last point', () {
    final early = week(0, inputs(55));
    final trend = OverallTrend.of(
      [week(2, inputs(70)), week(1, inputs(65)), week(0, null)],
      current: (
        date: monday.addDays(3),
        inputs: early.inputs,
        result: early.result,
      ),
    )!;

    expect(trend.points, hasLength(4));
    expect(trend.points[2].score, isNull);
    expect(trend.points.last.date, monday.addDays(3));
    expect(trend.now, scoreOf(inputs(55)));
    expect(trend.since.change, scoreOf(inputs(55)) - scoreOf(inputs(70)));
  });

  test('the current week is not added twice when it is the last Monday', () {
    final last = week(0, inputs(60));
    final trend = OverallTrend.of([week(1, inputs(70)), last], current: last)!;

    expect(trend.points, hasLength(2));
  });

  test('changes list the factors present in both weeks', () {
    final trend = OverallTrend.of([
      week(1, inputs(70)),
      week(0, inputs(60, waist: 0.48)),
    ])!;
    final byFactor = {for (final c in trend.changes) c.factor: c.points};

    expect(byFactor.containsKey(OverallFactor.body), isFalse);
    expect(byFactor[OverallFactor.restingHeartRate], closeTo(5, 1e-9));
    expect(byFactor[OverallFactor.sleepDuration], closeTo(0, 1e-9));
  });
}
