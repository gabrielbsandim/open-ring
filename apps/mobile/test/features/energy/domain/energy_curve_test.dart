import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';

final _from = DateTime.utc(2026, 11, 10);
final _to = DateTime.utc(2026, 11, 11);

DateTime _at(int hour, [int minute = 0]) =>
    _from.add(Duration(hours: hour, minutes: minute));

StepBucket _bucket(int hour, int steps) =>
    (start: _at(hour), duration: const Duration(hours: 1), steps: steps);

EnergyWorkout _workout(DateTime start, int minutes, double stored) => (
  start: start,
  end: start.add(Duration(minutes: minutes)),
  elapsed: Duration(minutes: minutes),
  met: 6,
  storedKilocalories: stored,
);

EnergyCurve _curve({
  required DateTime now,
  EnergySex? sex = EnergySex.male,
  int? age = 30,
  Iterable<StepBucket> slots = const [],
  Iterable<EnergyWorkout> workouts = const [],
}) => energyCurve(
  sex: sex,
  age: age,
  kilograms: 70,
  centimeters: 175,
  slots: slots,
  workouts: workouts,
  from: _from,
  to: _to,
  now: now,
);

EnergyDayEstimate _day({
  required DateTime now,
  Iterable<StepBucket> slots = const [],
  Iterable<EnergyWorkout> workouts = const [],
}) => energyDay(
  sex: EnergySex.male,
  age: 30,
  kilograms: 70,
  centimeters: 175,
  slots: slots,
  workouts: workouts,
  from: _from,
  to: _to,
  now: now,
) as EnergyDayEstimate;

void main() {
  test('has one point per full hour and one at the instant', () {
    final curve = _curve(now: _at(14, 30));

    expect(curve.from, _from);
    expect(curve.to, _to);
    expect(curve.points, hasLength(16));
    expect(curve.points.first.at, _from);
    expect(curve.points[14].at, _at(14));
    expect(curve.points.last.at, _at(14, 30));
  });

  test('an instant on the hour is not repeated', () {
    final curve = _curve(now: _at(14));

    expect(curve.points, hasLength(15));
    expect(curve.points.last.at, _at(14));
    expect(curve.points[13].at, _at(13));
  });

  test('starts at nothing and the Base grows with the hours', () {
    final curve = _curve(now: _at(14, 30));
    final resting = curve.points.last.day.resting;

    expect(curve.points.first.day.total, 0);
    expect(
      curve.points[6].day.base,
      closeTo(baseEnergy(resting, const Duration(hours: 6)), 1e-9),
    );
  });

  test('the last point is the day itself', () {
    final slots = [_bucket(8, 1200), _bucket(13, 900)];
    final workouts = [_workout(_at(10, 15), 40, 305)];
    final now = _at(14, 30);

    final last = _curve(now: now, slots: slots, workouts: workouts).points.last;
    final day = _day(now: now, slots: slots, workouts: workouts);

    expect(last.day.base, day.base);
    expect(last.day.steps, day.steps);
    expect(last.day.workouts, day.workouts);
  });

  test('steps count from the hour after their slot starts', () {
    final curve = _curve(now: _at(12), slots: [_bucket(8, 1200)]);

    expect(curve.points[8].day.steps, 0);
    expect(curve.points[9].day.steps, greaterThan(0));
    expect(curve.points[9].day.steps, curve.points.last.day.steps);
  });

  test('a workout counts from the hour after it starts', () {
    final curve = _curve(
      now: _at(12),
      workouts: [_workout(_at(10, 15), 40, 305)],
    );

    expect(curve.points[10].day.workouts, 0);
    expect(curve.points[11].day.workouts, 305);
  });

  test('the total never goes down', () {
    final curve = _curve(
      now: _at(20, 10),
      slots: [_bucket(8, 1200), _bucket(10, 3000), _bucket(18, 400)],
      workouts: [_workout(_at(10, 15), 40, 305)],
    );

    for (var i = 1; i < curve.points.length; i++) {
      expect(
        curve.points[i].day.total,
        greaterThanOrEqualTo(curve.points[i - 1].day.total),
        reason: 'point $i',
      );
    }
  });

  test('an instant past the day ends at the end of the day', () {
    final curve = _curve(now: _to.add(const Duration(hours: 3)));

    expect(curve.points, hasLength(25));
    expect(curve.points.last.at, _to);
  });

  test('an instant before the day has no point', () {
    final curve = _curve(now: _from.subtract(const Duration(minutes: 1)));

    expect(curve.points, isEmpty);
  });

  test('a profile without a sex has no point', () {
    expect(_curve(now: _at(12), sex: null).points, isEmpty);
  });

  test('an underage profile has no point', () {
    expect(_curve(now: _at(12), age: 16).points, isEmpty);
  });
}
