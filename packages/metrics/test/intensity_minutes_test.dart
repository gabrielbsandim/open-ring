import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

final start = DateTime.utc(2026, 11, 15, 10);

List<BpmSample> steady(int bpm, {required int samples, int everySeconds = 5}) =>
    [
      for (var i = 0; i < samples; i++)
        (at: start.add(Duration(seconds: i * everySeconds)), bpm: bpm),
    ];

StepBucket bucket(int minuteOffset, int steps) => (
  start: start.add(Duration(minutes: minuteOffset)),
  duration: const Duration(minutes: 15),
  steps: steps,
);

void main() {
  test('a vigorous minute counts as two moderate ones', () {
    const minutes = IntensityMinutes(moderate: 30, vigorous: 20);

    expect(minutes.equivalent, 70);
    expect((minutes + minutes).equivalent, 140);
    expect(IntensityMinutes.none.equivalent, 0);
  });

  group('by heart rate', () {
    test('moderate starts at 64 percent of max and vigorous at 77', () {
      IntensityMinutes at(int bpm) =>
          heartRateIntensity(steady(bpm, samples: 13), maxHeartRate: 200);

      expect(at(127).equivalent, 0);
      expect(at(128).moderate, closeTo(1, 1e-9));
      expect(at(153).moderate, closeTo(1, 1e-9));
      expect(at(154).vigorous, closeTo(1, 1e-9));
      expect(at(154).moderate, 0);
    });

    test('a sample is held for at most ten seconds', () {
      final result = heartRateIntensity([
        (at: start, bpm: 140),
        (at: start.add(const Duration(minutes: 5)), bpm: 140),
      ], maxHeartRate: 200);

      expect(result.moderate, closeTo(10 / 60, 1e-9));
    });

    test('zero readings and a single sample earn nothing', () {
      expect(
        heartRateIntensity(
          steady(0, samples: 20),
          maxHeartRate: 200,
        ).equivalent,
        0,
      );
      expect(
        heartRateIntensity(
          steady(170, samples: 1),
          maxHeartRate: 200,
        ).equivalent,
        0,
      );
    });

    test('a max heart rate out of range is refused', () {
      expect(
        () => heartRateIntensity(const [], maxHeartRate: 90),
        throwsArgumentError,
      );
    });
  });

  group('by workout type', () {
    const session = Duration(minutes: 45);

    test('under 3 MET earns nothing, 3 is moderate and 6 is vigorous', () {
      expect(metIntensity(2.5, session).equivalent, 0);
      expect(metIntensity(3, session).moderate, 45);
      expect(metIntensity(5.9, session).moderate, 45);
      expect(metIntensity(6, session).vigorous, 45);
      expect(metIntensity(6, session).equivalent, 90);
      expect(metIntensity(9.8, Duration.zero).equivalent, 0);
    });

    test('a workout without heart rate is credited by its type', () {
      final result = workoutIntensity(met: 3.5, elapsed: session);

      expect(result.moderate, 45);
    });

    test('a workout takes the larger of the two credits', () {
      final calm = steady(100, samples: 541);
      final hard = steady(170, samples: 541);

      final strength = workoutIntensity(
        met: 3.5,
        elapsed: session,
        heartRate: calm,
        maxHeartRate: 200,
      );
      final intervals = workoutIntensity(
        met: 3.5,
        elapsed: session,
        heartRate: hard,
        maxHeartRate: 200,
      );

      expect(strength.equivalent, 45);
      expect(intervals.vigorous, closeTo(45, 1e-9));
      expect(intervals.equivalent, closeTo(90, 1e-9));
    });
  });

  group('walking', () {
    test('a bucket counts from 100 steps a minute', () {
      expect(walkingIntensity([bucket(0, 1499)]).equivalent, 0);
      expect(walkingIntensity([bucket(0, 1500)]).moderate, 15);
      expect(
        walkingIntensity([bucket(0, 1600), bucket(15, 1700)]).moderate,
        30,
      );
    });

    test('a bucket that touches a workout is left to the workout', () {
      final workout = (
        start: start.add(const Duration(minutes: 20)),
        end: start.add(const Duration(minutes: 50)),
      );

      final result = walkingIntensity(
        [bucket(0, 1600), bucket(15, 1600), bucket(45, 1600), bucket(60, 1600)],
        workouts: [workout],
      );

      expect(result.moderate, 30);
    });

    test('an empty bucket is ignored', () {
      final empty = (start: start, duration: Duration.zero, steps: 500);

      expect(walkingIntensity([empty]).equivalent, 0);
    });
  });

  group('the weekly sum', () {
    const today = LocalDate(2026, 11, 15);
    DailyValue day(int ago, double minutes) =>
        (date: today.addDays(-ago), value: minutes);

    test('adds today and the six days before it', () {
      final total = weeklyIntensityMinutes([
        day(0, 20),
        day(1, 0),
        day(3, 45),
        day(6, 30),
        day(7, 500),
        day(-1, 500),
      ], today: today);

      expect(total, 95);
    });

    test('needs four days of data, and a rest day is a day of data', () {
      final three = [day(0, 60), day(1, 60), day(2, 60)];

      expect(weeklyIntensityMinutes(three, today: today), isNull);
      expect(weeklyIntensityMinutes([...three, day(3, 0)], today: today), 180);
    });

    test('a date given twice counts once, and bad values are dropped', () {
      final total = weeklyIntensityMinutes([
        day(0, 10),
        day(0, 30),
        day(1, 10),
        day(2, 10),
        day(3, 10),
        day(4, double.nan),
        day(5, -5),
      ], today: today);

      expect(total, 60);
    });

    test('a window or minimum out of range is refused', () {
      expect(
        () => weeklyIntensityMinutes(const [], today: today, windowDays: 0),
        throwsArgumentError,
      );
      expect(
        () => weeklyIntensityMinutes(const [], today: today, minDays: 8),
        throwsArgumentError,
      );
    });
  });
}
