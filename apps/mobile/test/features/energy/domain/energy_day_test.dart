import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';

final _from = DateTime.utc(2026, 11, 10);
final _to = DateTime.utc(2026, 11, 11);
final DateTime _noon = _from.add(const Duration(hours: 12));

StepBucket _bucket(int hour, int steps, {int minutes = 60, int minute = 0}) => (
  start: _from.add(Duration(hours: hour, minutes: minute)),
  duration: Duration(minutes: minutes),
  steps: steps,
);

EnergyWorkout _workout(
  DateTime start,
  int minutes, {
  double met = 6,
  double? stored,
  Duration? elapsed,
}) => (
  start: start,
  end: start.add(Duration(minutes: minutes)),
  elapsed: elapsed ?? Duration(minutes: minutes),
  met: met,
  storedKilocalories: stored,
);

DateTime _at(int hour, [int minute = 0]) =>
    _from.add(Duration(hours: hour, minutes: minute));

EnergyDay _day({
  EnergySex? sex = EnergySex.male,
  int? age = 30,
  double? kilograms = 70,
  double? centimeters = 175,
  Iterable<StepBucket> slots = const [],
  Iterable<EnergyWorkout> workouts = const [],
  DateTime? now,
}) => energyDay(
  sex: sex,
  age: age,
  kilograms: kilograms,
  centimeters: centimeters,
  slots: slots,
  workouts: workouts,
  from: _from,
  to: _to,
  now: now ?? _noon,
);

EnergyDayEstimate _estimate({
  Iterable<StepBucket> slots = const [],
  Iterable<EnergyWorkout> workouts = const [],
  DateTime? now,
}) {
  final day = _day(slots: slots, workouts: workouts, now: now);
  expect(day, isA<EnergyDayEstimate>());
  return day as EnergyDayEstimate;
}

Matcher _missing(Set<EnergyField> fields) =>
    isA<EnergyDayMissing>().having((m) => m.fields, 'fields', fields);

double _resting() => restingEnergy(
  sex: EnergySex.male,
  age: 30,
  kilograms: 70,
  centimeters: 175,
)!;

double _walk(num steps) =>
    stepEnergy(steps: steps.round(), kilograms: 70, centimeters: 175);

void main() {
  group('missing and underage', () {
    test('a missing sex alone is named', () {
      expect(_day(sex: null), _missing({EnergyField.sex}));
    });

    test('a missing age is the birth year', () {
      expect(_day(age: null), _missing({EnergyField.birthYear}));
    });

    test('a missing height alone is named', () {
      expect(_day(centimeters: null), _missing({EnergyField.height}));
    });

    test('a missing weight alone is named', () {
      expect(_day(kilograms: null), _missing({EnergyField.weight}));
    });

    test('several missing fields are all named', () {
      expect(
        _day(sex: null, kilograms: null, centimeters: null),
        _missing({EnergyField.sex, EnergyField.height, EnergyField.weight}),
      );
    });

    test('every field missing names all four', () {
      expect(
        _day(sex: null, age: null, kilograms: null, centimeters: null),
        _missing(EnergyField.values.toSet()),
      );
    });

    test('a known age under 18 is underage', () {
      expect(_day(age: 17), isA<EnergyDayUnderage>());
    });

    test('age 18 is an adult', () {
      expect(_day(age: 18), isA<EnergyDayEstimate>());
    });

    test('underage wins over another missing field', () {
      expect(_day(age: 12, sex: null), isA<EnergyDayUnderage>());
      expect(_day(age: 12, kilograms: null), isA<EnergyDayUnderage>());
    });
  });

  group('base', () {
    test('base is the resting burn of the elapsed part of the day', () {
      final estimate = _estimate();

      expect(estimate.resting, closeTo(_resting(), 1e-9));
      expect(
        estimate.base,
        closeTo(baseEnergy(_resting(), const Duration(hours: 12)), 1e-9),
      );
    });

    test('base is zero when now is before the day', () {
      final estimate = _estimate(now: _from.subtract(const Duration(hours: 3)));

      expect(estimate.base, 0);
    });

    test('base is the whole day when now is after it', () {
      final estimate = _estimate(now: _to.add(const Duration(hours: 5)));

      expect(
        estimate.base,
        closeTo(baseEnergy(_resting(), const Duration(hours: 24)), 1e-9),
      );
    });

    test('base is zero at the first instant and whole at the last', () {
      expect(_estimate(now: _from).base, 0);
      expect(
        _estimate(now: _to).base,
        closeTo(baseEnergy(_resting(), const Duration(hours: 24)), 1e-9),
      );
    });

    test('now is compared as an instant, whatever its zone', () {
      final local = _noon.toLocal();

      expect(_estimate(now: local).base, closeTo(_estimate().base, 1e-9));
    });
  });

  group('steps', () {
    test('steps are the step energy of the counted steps', () {
      final estimate = _estimate(
        slots: [_bucket(8, 1000), _bucket(9, 2000), _bucket(15, 500)],
      );

      expect(estimate.steps, closeTo(_walk(3500), 1e-9));
    });

    test('no slots count no steps', () {
      expect(_estimate().steps, 0);
    });

    test('a slot half covered by a workout counts half its steps', () {
      final estimate = _estimate(
        slots: [_bucket(10, 1000)],
        workouts: [_workout(_at(10), 30, stored: 0)],
      );

      expect(estimate.steps, closeTo(_walk(500), 1e-9));
    });

    test('a slot fully covered counts none', () {
      final estimate = _estimate(
        slots: [_bucket(10, 1000)],
        workouts: [_workout(_at(9, 30), 120, stored: 0)],
      );

      expect(estimate.steps, 0);
    });

    test('two workouts over the same minutes subtract once', () {
      final estimate = _estimate(
        slots: [_bucket(10, 1000)],
        workouts: [
          _workout(_at(10), 30, stored: 0),
          _workout(_at(10), 30, stored: 0),
        ],
      );

      expect(estimate.steps, closeTo(_walk(500), 1e-9));
    });

    test('partly overlapping workouts cover the union of their minutes', () {
      final estimate = _estimate(
        slots: [_bucket(10, 1000)],
        workouts: [
          _workout(_at(10), 30, stored: 0),
          _workout(_at(10, 15), 30, stored: 0),
        ],
      );

      expect(estimate.steps, closeTo(_walk(250), 1e-9));
    });

    test('many workouts over one slot never remove more than its steps', () {
      final estimate = _estimate(
        slots: [_bucket(10, 1000)],
        workouts: [
          for (var i = 0; i < 5; i++) _workout(_at(10), 60, stored: 0),
        ],
      );

      expect(estimate.steps, 0);
    });

    test('a zero duration slot inside a workout counts no steps', () {
      final estimate = _estimate(
        slots: [_bucket(10, 100, minutes: 0, minute: 10)],
        workouts: [_workout(_at(10), 30, stored: 0)],
      );

      expect(estimate.steps, 0);
    });

    test('a zero duration slot outside a workout counts all its steps', () {
      final estimate = _estimate(
        slots: [_bucket(11, 100, minutes: 0)],
        workouts: [_workout(_at(10), 30, stored: 0)],
      );

      expect(estimate.steps, closeTo(_walk(100), 1e-9));
    });

    test('a workout with no length covers nothing and adds nothing', () {
      final estimate = _estimate(
        slots: [_bucket(10, 1000)],
        workouts: [
          (
            start: _at(10, 15),
            end: _at(10, 15),
            elapsed: Duration.zero,
            met: 6,
            storedKilocalories: null,
          ),
        ],
      );

      expect(estimate.steps, closeTo(_walk(1000), 1e-9));
      expect(estimate.workouts, 0);
    });

    test('a workout that ends before it starts covers nothing', () {
      final estimate = _estimate(
        slots: [_bucket(10, 1000)],
        workouts: [
          (
            start: _at(10, 30),
            end: _at(10),
            elapsed: Duration.zero,
            met: 6,
            storedKilocalories: null,
          ),
        ],
      );

      expect(estimate.steps, closeTo(_walk(1000), 1e-9));
      expect(estimate.workouts.isFinite, isTrue);
      expect(estimate.workouts, 0);
    });

    test('workout instants are compared whatever their zone', () {
      final estimate = _estimate(
        slots: [_bucket(10, 1000)],
        workouts: [
          (
            start: _at(10).toLocal(),
            end: _at(10, 30).toLocal(),
            elapsed: const Duration(minutes: 30),
            met: 6,
            storedKilocalories: 0,
          ),
        ],
      );

      expect(estimate.steps, closeTo(_walk(500), 1e-9));
    });
  });

  group('workouts', () {
    test('a stored kilocalorie count is added as it is', () {
      final estimate = _estimate(
        workouts: [_workout(_at(10), 30, stored: 250)],
      );

      expect(estimate.workouts, 250);
    });

    test('with none stored the workout is estimated from its intensity', () {
      final estimate = _estimate(
        workouts: [
          _workout(_at(10), 60, met: 8, elapsed: const Duration(minutes: 45)),
        ],
      );

      expect(
        estimate.workouts,
        closeTo(
          workoutEnergy(
            met: 8,
            kilograms: 70,
            elapsed: const Duration(minutes: 45),
          ),
          1e-9,
        ),
      );
    });

    test('workouts add up', () {
      final estimate = _estimate(
        workouts: [_workout(_at(8), 30, stored: 200), _workout(_at(18), 30)],
      );

      expect(
        estimate.workouts,
        closeTo(
          200 +
              workoutEnergy(
                met: 6,
                kilograms: 70,
                elapsed: const Duration(minutes: 30),
              ),
          1e-9,
        ),
      );
    });

    test('a workout starting exactly at the day start adds its kcal', () {
      final estimate = _estimate(workouts: [_workout(_from, 30, stored: 120)]);

      expect(estimate.workouts, 120);
    });

    test('a workout starting exactly at the day end adds nothing', () {
      final estimate = _estimate(workouts: [_workout(_to, 30, stored: 120)]);

      expect(estimate.workouts, 0);
    });

    test('a workout that started before the day adds no kcal', () {
      final estimate = _estimate(
        workouts: [
          _workout(
            _from.subtract(const Duration(minutes: 30)),
            60,
            stored: 300,
          ),
        ],
      );

      expect(estimate.workouts, 0);
    });

    test('a workout that started before the day still removes its steps', () {
      final estimate = _estimate(
        slots: [_bucket(0, 1000)],
        workouts: [
          _workout(
            _from.subtract(const Duration(minutes: 30)),
            60,
            stored: 300,
          ),
        ],
      );

      expect(estimate.steps, closeTo(_walk(500), 1e-9));
      expect(estimate.workouts, 0);
    });
  });

  group('total and range', () {
    test('the total is base plus steps plus workouts', () {
      const estimate = EnergyDayEstimate(
        resting: 1600,
        base: 900.4,
        steps: 120.3,
        workouts: 250.2,
      );

      expect(estimate.total, closeTo(1270.9, 1e-9));
    });

    test('the range is taken on the unrounded sum', () {
      const estimate = EnergyDayEstimate(
        resting: 1600,
        base: 1282,
        steps: 0.4,
        workouts: 0.4,
      );

      expect(estimate.range, (low: 1100, high: 1500));
    });

    test('a computed day carries the range of its total', () {
      final estimate = _estimate(
        slots: [_bucket(9, 4000)],
        workouts: [_workout(_at(10), 30, stored: 310)],
      );

      expect(
        estimate.total,
        closeTo(estimate.base + estimate.steps + estimate.workouts, 1e-9),
      );
      expect(estimate.range, energyRange(estimate.total, energyDayMargin));
    });
  });
  group('the usual day', () {
    EnergyDayEstimate day(double steps) =>
        EnergyDayEstimate(resting: 1700, base: 2000, steps: steps, workouts: 0);

    test('needs the minimum of days', () {
      expect(energyUsual([day(100), day(200)]), isNull);
      expect(energyUsual([day(100), day(200), day(600)]), 2300);
    });

    test('a day with steps or a workout is on record', () {
      expect(energyDayOnRecord(day(1)), isTrue);
      expect(energyDayOnRecord(day(0)), isFalse);
      expect(
        energyDayOnRecord(
          const EnergyDayEstimate(
            resting: 1700,
            base: 2000,
            steps: 0,
            workouts: 120,
          ),
        ),
        isTrue,
      );
    });
  });
}
