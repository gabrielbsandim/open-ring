import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const monday = LocalDate(2026, 12, 7);
const saoPaulo = Duration(hours: -3);

LocalDate dec(int day) => LocalDate(2026, 12, day);

DateTime _local(LocalDate date, int minuteOfDay, Duration offset) =>
    DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).add(Duration(minutes: minuteOfDay)).subtract(offset);

// A night dated [date] by its end, with one asleep span from the onset to the end.
SleepNight night(
  LocalDate date, {
  required int onset,
  int end = 420,
  Duration offset = Duration.zero,
}) {
  final onsetDate = onset >= 720 ? date.addDays(-1) : date;
  return SleepNight([
    SleepSpan(
      start: _local(onsetDate, onset, offset),
      end: _local(date, end, offset),
      phase: SleepPhase.light,
      utcOffset: offset,
    ),
  ]);
}

int clock(int hour, int minute) => hour * 60 + minute;

const stepsLever = Lever(kind: LeverKind.steps, target: 10000);
const sleepLever = Lever(kind: LeverKind.sleepWindow, target: 690);
const wakeLever = Lever(kind: LeverKind.wakeTime, target: 405);
const strengthLever = Lever(kind: LeverKind.strengthDays, target: 2);
const effortLever = Lever(kind: LeverKind.effortPoints, target: 165);

const LeverDayMark met = LeverDayMark.met;
const LeverDayMark missed = LeverDayMark.missed;
const LeverDayMark open = LeverDayMark.open;
const LeverDayMark ahead = LeverDayMark.ahead;

final Map<LocalDate, int> weekSteps = {
  dec(7): 10420,
  dec(8): 8310,
  dec(9): 11050,
  dec(10): 8640,
};

void main() {
  group('criterion 1: a steps lever marks each day against the target', () {
    test('marks met, missed, met, open and three ahead on Thursday', () {
      final progress = leverProgress(
        stepsLever,
        GoalWeekData(steps: weekSteps),
        monday: monday,
        today: dec(10),
      );

      expect(progress.days, [met, missed, met, open, ahead, ahead, ahead]);
    });

    test('counts the two met days as achieved', () {
      final progress = leverProgress(
        stepsLever,
        GoalWeekData(steps: weekSteps),
        monday: monday,
        today: dec(10),
      );

      expect(progress.achieved, 2);
    });

    test('a lower target of 9000 gives the same marks and count', () {
      final progress = leverProgress(
        const Lever(kind: LeverKind.steps, target: 9000),
        GoalWeekData(steps: weekSteps),
        monday: monday,
        today: dec(10),
      );

      expect(progress.days, [met, missed, met, open, ahead, ahead, ahead]);
      expect(progress.achieved, 2);
    });

    test('a day exactly on the target is met', () {
      final progress = leverProgress(
        stepsLever,
        GoalWeekData(steps: {dec(7): 10000, dec(8): 9999}),
        monday: monday,
        today: dec(10),
      );

      expect(progress.days!.take(2), [met, missed]);
    });

    test(
      'keeps the lever and the count in the week it hands to the review',
      () {
        final progress = leverProgress(
          stepsLever,
          GoalWeekData(steps: weekSteps),
          monday: monday,
          today: dec(10),
        );

        expect(progress.lever, same(stepsLever));
        expect(progress.week.lever, same(stepsLever));
        expect(progress.week.achieved, 2);
      },
    );
  });

  group('criterion 2: a sleep window lever marks each night', () {
    final nights = {
      dec(7): night(dec(7), onset: clock(23, 20)),
      dec(8): night(dec(8), onset: clock(23, 10)),
      dec(9): night(dec(9), onset: clock(0, 5)),
      dec(10): night(dec(10), onset: clock(23, 25)),
    };

    test('marks met, met, missed, met and three ahead', () {
      final progress = leverProgress(
        sleepLever,
        GoalWeekData(nights: nights),
        monday: monday,
        today: dec(10),
      );

      expect(progress.days, [met, met, missed, met, ahead, ahead, ahead]);
    });

    test('counts three achieved nights', () {
      final progress = leverProgress(
        sleepLever,
        GoalWeekData(nights: nights),
        monday: monday,
        today: dec(10),
      );

      expect(progress.achieved, 3);
    });

    test('a night with no data on a past day is missed', () {
      final progress = leverProgress(
        sleepLever,
        const GoalWeekData(),
        monday: monday,
        today: dec(10),
      );

      expect(progress.days, [
        missed,
        missed,
        missed,
        open,
        ahead,
        ahead,
        ahead,
      ]);
      expect(progress.achieved, 0);
    });
  });

  group('criterion 3: clock values in whole local minutes', () {
    test('23:30:40 is 690 minutes after noon, the seconds dropped', () {
      expect(
        minutesAfterNoon(DateTime.utc(2026, 12, 7, 23, 30, 40), Duration.zero),
        690,
      );
    });

    test('00:05 is 725 minutes after noon', () {
      expect(
        minutesAfterNoon(DateTime.utc(2026, 12, 8, 0, 5), Duration.zero),
        725,
      );
    });

    test('11:00 is 1380 minutes after noon', () {
      expect(
        minutesAfterNoon(DateTime.utc(2026, 12, 7, 11), Duration.zero),
        1380,
      );
    });

    test('noon is 0 minutes after noon', () {
      expect(minutesAfterNoon(DateTime.utc(2026, 12, 7, 12), Duration.zero), 0);
    });

    test('the offset moves the instant onto the local clock', () {
      expect(minutesAfterNoon(DateTime.utc(2026, 12, 8, 2, 30), saoPaulo), 690);
    });

    test('minutes after midnight reads 06:15:50 as 375', () {
      expect(
        minutesAfterMidnight(
          DateTime.utc(2026, 12, 7, 6, 15, 50),
          Duration.zero,
        ),
        375,
      );
    });

    test('minutes after midnight follows the offset', () {
      expect(
        minutesAfterMidnight(DateTime.utc(2026, 12, 7, 9, 15), saoPaulo),
        375,
      );
    });

    test('minutes after midnight wraps a negative offset past midnight', () {
      expect(
        minutesAfterMidnight(DateTime.utc(2026, 12, 7, 1), saoPaulo),
        1320,
      );
    });
  });

  group('bedtimeMet', () {
    test('an onset exactly at the target is met', () {
      expect(bedtimeMet(night(dec(8), onset: clock(23, 30)), 690), isTrue);
    });

    test('an onset one minute after the target is not met', () {
      expect(bedtimeMet(night(dec(8), onset: clock(23, 31)), 690), isFalse);
    });

    test('reads the onset with the offset of its span', () {
      final local = night(dec(8), onset: clock(23, 20), offset: saoPaulo);

      expect(bedtimeMet(local, 690), isTrue);
    });

    test('the onset skips a leading awake span', () {
      final started = DateTime.utc(2026, 12, 7, 23);
      final asleep = DateTime.utc(2026, 12, 8, 0, 20);
      final woke = DateTime.utc(2026, 12, 8, 7);
      final lateNight = SleepNight([
        SleepSpan(
          start: started,
          end: asleep,
          phase: SleepPhase.awake,
          utcOffset: Duration.zero,
        ),
        SleepSpan(
          start: asleep,
          end: woke,
          phase: SleepPhase.deep,
          utcOffset: Duration.zero,
        ),
      ]);

      expect(bedtimeMet(lateNight, 690), isFalse);
    });

    test('a night with no asleep span is not met', () {
      final awake = SleepNight([
        SleepSpan(
          start: DateTime.utc(2026, 12, 7, 22),
          end: DateTime.utc(2026, 12, 8, 6),
          phase: SleepPhase.awake,
          utcOffset: Duration.zero,
        ),
      ]);

      expect(bedtimeMet(awake, 1380), isFalse);
    });

    test('a nap that is the main night reads 120 and is met', () {
      final nap = night(dec(8), onset: clock(14, 0), end: clock(15, 30));

      expect(minutesAfterNoon(nap.sleepOnset!, Duration.zero), 120);
      expect(bedtimeMet(nap, 690), isTrue);
    });
  });

  group('criterion 4: a wake time lever is met within the tolerance', () {
    test('an end at 06:15 is met', () {
      expect(
        wakeMet(night(dec(8), onset: 1380, end: clock(6, 15)), 405),
        isTrue,
      );
    });

    test('an end at 07:15 is met', () {
      expect(
        wakeMet(night(dec(8), onset: 1380, end: clock(7, 15)), 405),
        isTrue,
      );
    });

    test('an end at 07:16 is missed', () {
      expect(
        wakeMet(night(dec(8), onset: 1380, end: clock(7, 16)), 405),
        isFalse,
      );
    });

    test('an end at 06:14 is missed', () {
      expect(
        wakeMet(night(dec(8), onset: 1380, end: clock(6, 14)), 405),
        isFalse,
      );
    });

    test('the tolerance is the one the review module names', () {
      expect(goalWakeToleranceMinutes, 30);
    });

    test(
      'a wake just before midnight is within reach of a target after it',
      () {
        final lateWake = night(dec(8), onset: clock(15, 0), end: clock(23, 50));

        expect(wakeMet(lateWake, 10), isTrue);
      },
    );

    test(
      'a wake just after midnight is within reach of a target before it',
      () {
        final early = night(dec(8), onset: clock(15, 0), end: clock(0, 10));

        expect(wakeMet(early, 1430), isTrue);
      },
    );

    test('reads the end with the offset of the last span', () {
      final local = night(
        dec(8),
        onset: clock(23, 0),
        end: clock(6, 30),
        offset: saoPaulo,
      );

      expect(wakeMet(local, 405), isTrue);
    });

    test('a trailing awake span moves the wake to its end', () {
      final slept = DateTime.utc(2026, 12, 8, 7);
      final up = DateTime.utc(2026, 12, 8, 7, 50);
      final trailing = SleepNight([
        SleepSpan(
          start: DateTime.utc(2026, 12, 7, 23),
          end: slept,
          phase: SleepPhase.light,
          utcOffset: Duration.zero,
        ),
        SleepSpan(
          start: slept,
          end: up,
          phase: SleepPhase.awake,
          utcOffset: Duration.zero,
        ),
      ]);

      expect(wakeMet(trailing, 405), isFalse);
    });

    test('marks a wake lever from the end of each night', () {
      final progress = leverProgress(
        wakeLever,
        GoalWeekData(
          nights: {
            dec(7): night(dec(7), onset: 1380, end: clock(6, 15)),
            dec(8): night(dec(8), onset: 1380, end: clock(7, 16)),
          },
        ),
        monday: monday,
        today: dec(9),
      );

      expect(progress.days, [met, missed, open, ahead, ahead, ahead, ahead]);
      expect(progress.achieved, 1);
    });
  });

  group('criterion 5: a strength days lever counts the days of the week', () {
    final days = {dec(7), const LocalDate(2026, 11, 30), dec(12)};

    test('counts only the days from Monday to today', () {
      final progress = leverProgress(
        strengthLever,
        GoalWeekData(strengthDays: days),
        monday: monday,
        today: dec(10),
      );

      expect(progress.achieved, 1);
    });

    test('has no day marks for a weekly lever', () {
      final progress = leverProgress(
        strengthLever,
        GoalWeekData(strengthDays: days),
        monday: monday,
        today: dec(10),
      );

      expect(progress.days, isNull);
    });

    test('counts Sunday and stops there when today is the next Monday', () {
      final progress = leverProgress(
        strengthLever,
        GoalWeekData(strengthDays: {dec(13), dec(14)}),
        monday: monday,
        today: dec(14),
      );

      expect(progress.achieved, 1);
    });

    test('counts nothing for an empty set', () {
      final progress = leverProgress(
        strengthLever,
        const GoalWeekData(),
        monday: monday,
        today: dec(10),
      );

      expect(progress.achieved, 0);
    });
  });

  group('criterion 6: an effort points lever sums the finite points', () {
    DailyValue point(LocalDate date, double value) =>
        (date: date, value: value);

    test('sums Monday to today and leaves out the day before, and NaN', () {
      final progress = leverProgress(
        effortLever,
        GoalWeekData(
          points: [
            point(dec(7), 45),
            point(dec(9), 80),
            point(dec(10), 15),
            point(dec(6), 99),
            point(dec(8), double.nan),
          ],
        ),
        monday: monday,
        today: dec(10),
      );

      expect(progress.achieved, 140);
      expect(progress.days, isNull);
    });

    test('leaves out a day after today', () {
      final progress = leverProgress(
        effortLever,
        GoalWeekData(points: [point(dec(10), 15), point(dec(11), 40)]),
        monday: monday,
        today: dec(10),
      );

      expect(progress.achieved, 15);
    });

    test('leaves out negative and infinite values', () {
      final progress = leverProgress(
        effortLever,
        GoalWeekData(
          points: [
            point(dec(7), 30),
            point(dec(8), -20),
            point(dec(9), double.infinity),
          ],
        ),
        monday: monday,
        today: dec(10),
      );

      expect(progress.achieved, 30);
    });

    test('rounds the sum, not each value', () {
      final progress = leverProgress(
        effortLever,
        GoalWeekData(points: [point(dec(7), 10.4), point(dec(8), 10.4)]),
        monday: monday,
        today: dec(10),
      );

      expect(progress.achieved, 21);
    });

    test('stops at Sunday when today is in the next week', () {
      final progress = leverProgress(
        effortLever,
        GoalWeekData(points: [point(dec(13), 50), point(dec(14), 70)]),
        monday: monday,
        today: dec(14),
      );

      expect(progress.achieved, 50);
    });

    test('is zero with no points', () {
      final progress = leverProgress(
        effortLever,
        const GoalWeekData(),
        monday: monday,
        today: dec(10),
      );

      expect(progress.achieved, 0);
    });
  });

  group('criterion 7: on Monday every later day is ahead', () {
    test('steps are open then six ahead and nothing achieved', () {
      final progress = leverProgress(
        stepsLever,
        GoalWeekData(steps: {dec(7): 190}),
        monday: monday,
        today: dec(7),
      );

      expect(progress.days, [open, ahead, ahead, ahead, ahead, ahead, ahead]);
      expect(progress.achieved, 0);
    });

    test('a met night is met then six ahead and one achieved', () {
      final progress = leverProgress(
        sleepLever,
        GoalWeekData(nights: {dec(7): night(dec(7), onset: clock(23, 20))}),
        monday: monday,
        today: dec(7),
      );

      expect(progress.days, [met, ahead, ahead, ahead, ahead, ahead, ahead]);
      expect(progress.achieved, 1);
    });

    test('a met day is met even while it is today', () {
      final progress = leverProgress(
        stepsLever,
        GoalWeekData(steps: {dec(10): 12000}),
        monday: monday,
        today: dec(10),
      );

      expect(progress.days![3], met);
    });
  });

  group('criterion 8: a closed week has no open and no ahead day', () {
    test('marks the days after the last data as missed', () {
      final progress = leverProgress(
        stepsLever,
        GoalWeekData(steps: weekSteps),
        monday: monday,
        today: dec(14),
      );

      expect(progress.days, [met, missed, met, missed, missed, missed, missed]);
      expect(progress.achieved, 2);
    });

    test('on Sunday itself the last day is open', () {
      final progress = leverProgress(
        stepsLever,
        GoalWeekData(steps: weekSteps),
        monday: monday,
        today: dec(13),
      );

      expect(progress.days, [met, missed, met, missed, missed, missed, open]);
    });
  });

  group('criterion 9: the number of the week in the block', () {
    const start = LocalDate(2026, 11, 16);
    final cases = <(LocalDate, int)>[
      (const LocalDate(2026, 11, 16), 1),
      (const LocalDate(2026, 11, 22), 1),
      (const LocalDate(2026, 11, 23), 2),
      (const LocalDate(2026, 12, 7), 4),
      (const LocalDate(2026, 12, 10), 4),
    ];

    for (final (today, expected) in cases) {
      test('a block started 2026-11-16 is week $expected on ${today.iso}', () {
        expect(goalWeekNumber(start: start, today: today), expected);
      });
    }

    test('a block started on a Wednesday is week 1 on 2026-11-29', () {
      expect(
        goalWeekNumber(
          start: const LocalDate(2026, 11, 18),
          today: const LocalDate(2026, 11, 29),
        ),
        1,
      );
    });

    test('a block started on a Wednesday is week 2 on 2026-11-30', () {
      expect(
        goalWeekNumber(
          start: const LocalDate(2026, 11, 18),
          today: const LocalDate(2026, 11, 30),
        ),
        2,
      );
    });

    test('a day before the start is week 1', () {
      expect(
        goalWeekNumber(start: start, today: const LocalDate(2026, 11, 10)),
        1,
      );
    });
  });
}
