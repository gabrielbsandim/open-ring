import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const end = LocalDate(2026, 11, 15);
const saoPaulo = Duration(hours: -3);

LocalDate nov(int day) => LocalDate(2026, 11, day);

DateTime _local(LocalDate date, int minuteOfDay, Duration offset) =>
    DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).add(Duration(minutes: minuteOfDay)).subtract(offset);

// A night dated [date] by its end, with one span of [phase] from onset to end.
SleepNight night(
  LocalDate date, {
  required int onset,
  int wake = 405,
  Duration offset = Duration.zero,
  SleepPhase phase = SleepPhase.light,
}) {
  final onsetDate = onset >= 720 ? date.addDays(-1) : date;
  return SleepNight([
    SleepSpan(
      start: _local(onsetDate, onset, offset),
      end: _local(date, wake, offset),
      phase: phase,
      utcOffset: offset,
    ),
  ]);
}

int clock(int hour, int minute) => hour * 60 + minute;

Map<LocalDate, int> stepsOnFourteenDays() => {
  for (var day = 2; day <= 8; day++) nov(day): 7800,
  for (var day = 9; day <= 15; day++) nov(day): 8200,
};

Map<LocalDate, SleepNight> sevenNights({Duration offset = Duration.zero}) => {
  for (var day = 9; day <= 15; day++)
    nov(day): night(
      nov(day),
      onset: clock(23, 45),
      wake: clock(6, 45),
      offset: offset,
    ),
};

Set<LocalDate> strengthOn(int count, {int firstDay = 1}) => {
  for (var i = 0; i < count; i++) LocalDate(2026, 11, firstDay + i),
};

void main() {
  group('case 1: the steps median of the short window', () {
    test('takes the middle of seven days at 7,800 and seven at 8,200', () {
      final baseline = leverBaseline(
        GoalWeekData(steps: stepsOnFourteenDays()),
        end: end,
      );

      expect(baseline.stepsMedian14, 8000);
    });

    test('is null with six days only', () {
      final baseline = leverBaseline(
        GoalWeekData(
          steps: {for (var day = 10; day <= 15; day++) nov(day): 8000},
        ),
        end: end,
      );

      expect(baseline.stepsMedian14, isNull);
    });

    test('is given by exactly seven days', () {
      final baseline = leverBaseline(
        GoalWeekData(
          steps: {for (var day = 9; day <= 15; day++) nov(day): 8000},
        ),
        end: end,
      );

      expect(baseline.stepsMedian14, 8000);
    });

    test('ignores a day before the short window', () {
      final baseline = leverBaseline(
        GoalWeekData(steps: {...stepsOnFourteenDays(), nov(1): 50000}),
        end: end,
      );

      expect(baseline.stepsMedian14, 8000);
    });

    test('does not count a day before the window toward the minimum', () {
      final baseline = leverBaseline(
        GoalWeekData(
          steps: {
            for (var day = 11; day <= 15; day++) nov(day): 8000,
            nov(1): 8000,
            LocalDate(2026, 10, 31): 8000,
          },
        ),
        end: end,
      );

      expect(baseline.stepsMedian14, isNull);
    });
  });

  group('case 2: medianOf', () {
    test('takes the middle of an odd count', () {
      expect(medianOf([3, 1, 2]), 2);
    });

    test('rounds the mean of the two middle values of an even count', () {
      expect(medianOf([1, 2]), 2);
      expect(medianOf([1, 2, 3, 4]), 3);
      expect(medianOf([10, 20]), 15);
    });

    test('is null when empty', () {
      expect(medianOf(const <int>[]), isNull);
    });

    test('is null under the minimum count', () {
      expect(medianOf([1, 2], minCount: 3), isNull);
    });

    test('is given at exactly the minimum count', () {
      expect(medianOf([1, 2, 3], minCount: 3), 2);
    });
  });

  group('case 3: the sleep medians', () {
    GoalWeekData sevenNightData({Duration offset = Duration.zero}) =>
        GoalWeekData(
          steps: stepsOnFourteenDays(),
          nights: sevenNights(offset: offset),
        );

    test('the bed median is minutes after noon of the first asleep span', () {
      final baseline = leverBaseline(sevenNightData(), end: end);

      expect(baseline.bedMedian, 705);
    });

    test('the wake median is minutes after midnight of the last end', () {
      final baseline = leverBaseline(sevenNightData(), end: end);

      expect(baseline.wakeMedian, 405);
    });

    test('reads both medians on the clock of the span offset', () {
      final baseline = leverBaseline(
        sevenNightData(offset: saoPaulo),
        end: end,
      );

      expect(baseline.bedMedian, 705);
      expect(baseline.wakeMedian, 405);
    });

    test('are null with six nights', () {
      final nights = sevenNights()..remove(nov(15));
      final baseline = leverBaseline(GoalWeekData(nights: nights), end: end);

      expect(baseline.bedMedian, isNull);
      expect(baseline.wakeMedian, isNull);
    });

    test('a night with no asleep span is skipped from the bed median', () {
      final nights = sevenNights();
      nights[nov(15)] = night(
        nov(15),
        onset: clock(23, 45),
        phase: SleepPhase.awake,
      );
      final baseline = leverBaseline(GoalWeekData(nights: nights), end: end);

      expect(baseline.bedMedian, isNull);
    });

    test('the lever entry on that baseline gives sleep 690 and steps 9000', () {
      final baseline = leverBaseline(sevenNightData(), end: end);

      final sleep = leverEntry(
        LeverKind.sleepWindow,
        GoalKind.loseFat,
        baseline,
      );
      final steps = leverEntry(LeverKind.steps, GoalKind.loseFat, baseline);

      expect(sleep?.target, 690);
      expect(steps?.target, 9000);
    });
  });

  group('case 4: the effort mean of four weeks', () {
    final weekPoints = <DailyValue>[
      (date: LocalDate(2026, 10, 20), value: 135),
      (date: LocalDate(2026, 10, 27), value: 150),
      (date: nov(3), value: 145),
      (date: nov(10), value: 170),
    ];

    test('is the sum of the points over four', () {
      final baseline = leverBaseline(
        GoalWeekData(points: weekPoints),
        end: end,
      );

      expect(baseline.effortMean4Weeks, 150.0);
    });

    test('a NaN point adds nothing', () {
      final baseline = leverBaseline(
        GoalWeekData(
          points: [...weekPoints, (date: nov(12), value: double.nan)],
        ),
        end: end,
      );

      expect(baseline.effortMean4Weeks, 150.0);
    });

    test('a negative point adds nothing', () {
      final baseline = leverBaseline(
        GoalWeekData(points: [...weekPoints, (date: nov(12), value: -50)]),
        end: end,
      );

      expect(baseline.effortMean4Weeks, 150.0);
    });

    test('is null with no point in the window', () {
      final baseline = leverBaseline(
        GoalWeekData(
          points: [
            (date: LocalDate(2026, 10, 18), value: 500),
            (date: nov(16), value: 500),
          ],
        ),
        end: end,
      );

      expect(baseline.effortMean4Weeks, isNull);
    });

    test('is null with no points at all', () {
      final baseline = leverBaseline(const GoalWeekData(), end: end);

      expect(baseline.effortMean4Weeks, isNull);
    });
  });

  group('case 5: the usual strength days', () {
    test('six dates in the long window give 1', () {
      final baseline = leverBaseline(
        GoalWeekData(strengthDays: strengthOn(6)),
        end: end,
      );

      expect(baseline.strengthDaysUsual, 1);
    });

    test('three dates give 0', () {
      final baseline = leverBaseline(
        GoalWeekData(strengthDays: strengthOn(3)),
        end: end,
      );

      expect(baseline.strengthDaysUsual, 0);
    });

    test('eight dates give 2', () {
      final baseline = leverBaseline(
        GoalWeekData(strengthDays: strengthOn(8)),
        end: end,
      );

      expect(baseline.strengthDaysUsual, 2);
    });

    test('dates before the long window are not counted', () {
      final inside = strengthOn(4);
      final outside = {
        for (var day = 14; day <= 18; day++) LocalDate(2026, 10, day),
      };
      final baseline = leverBaseline(
        GoalWeekData(strengthDays: {...inside, ...outside}),
        end: end,
      );

      expect(baseline.strengthDaysUsual, 1);
    });
  });

  group('case 6: the readiness of a closed week', () {
    const last = LocalDate(2026, 12, 7);
    final trailing = <int?>[for (var value = 1; value <= 14; value++) value];

    test('the week from 11-30 reads 7 to 13', () {
      final week = weekReadiness(
        trailing,
        last: last,
        from: const LocalDate(2026, 11, 30),
      );

      expect(week, [7, 8, 9, 10, 11, 12, 13]);
    });

    test('the week from 11-23 starts with null then reads 1 to 6', () {
      final week = weekReadiness(
        trailing,
        last: last,
        from: const LocalDate(2026, 11, 23),
      );

      expect(week, [null, 1, 2, 3, 4, 5, 6]);
    });

    test('a day after last is null', () {
      final week = weekReadiness(
        trailing,
        last: last,
        from: const LocalDate(2026, 12, 5),
      );

      expect(week, [12, 13, 14, null, null, null, null]);
    });

    test('keeps a null value of the trailing list', () {
      final week = weekReadiness(
        [for (var value = 1; value <= 14; value++) value == 9 ? null : value],
        last: last,
        from: const LocalDate(2026, 11, 30),
      );

      expect(week, [7, 8, null, 10, 11, 12, 13]);
    });
  });
}
