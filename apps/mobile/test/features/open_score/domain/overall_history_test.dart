import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/domain/overall_history.dart';
import 'package:open_ring/features/sleep/application/sleep_source_selection.dart';

const today = LocalDate(2026, 11, 13);
const monday = LocalDate(2026, 11, 9);

LocalDate back(int days) => monday.addDays(-days);

SleepSpan span(LocalDate date, int hour, Duration length) {
  final start = DateTime.utc(date.year, date.month, date.day, hour);
  return SleepSpan(
    start: start,
    end: start.add(length),
    phase: SleepPhase.light,
    utcOffset: Duration.zero,
  );
}

SleepNight night(LocalDate date) =>
    SleepNight([span(date.addDays(-1), 23, const Duration(hours: 8))]);

List<BpmSample> nightHeart(LocalDate date, int bpm) => [
  for (var i = 0; i < 90; i++)
    (
      at: DateTime.utc(
        date.year,
        date.month,
        date.day - 1,
        23,
      ).add(Duration(minutes: 5 * i)),
      bpm: bpm,
    ),
];

List<BpmSample> dayHeart(LocalDate date) => [
  (at: DateTime.utc(date.year, date.month, date.day, 12), bpm: 70),
];

WeighIn weighIn(LocalDate date, double kilograms, {double? waist}) => WeighIn(
  id: date.day,
  at: DateTime.utc(date.year, date.month, date.day, 7),
  offsetMinutes: 0,
  kilograms: kilograms,
  waistCentimeters: waist,
  source: WeighInSource.manual,
);

OverallHistory collect({
  int days = 105,
  int extra = 0,
  Map<LocalDate, DayTag> tags = const {},
  List<WeighIn> weighIns = const [],
  double? heightCentimeters,
  int? birthYear,
  List<LocalDate> strengthDates = const [],
}) {
  final dates = [for (var age = days; age >= 1 - extra; age--) back(age)];
  return OverallHistory.collect(
    today: today,
    sessions: [
      for (final date in [...dates, monday]) night(date),
    ],
    heartRate: [
      for (final date in dates) ...[...nightHeart(date, 52), ...dayHeart(date)],
    ],
    utcOffset: Duration.zero,
    steps: [for (final date in dates) (date: date, value: 8000)],
    intensity: [for (final date in dates) (date: date, value: 30)],
    strengthDates: strengthDates,
    tags: tags,
    weighIns: weighIns,
    heightCentimeters: heightCentimeters,
    birthYear: birthYear,
  );
}

void main() {
  group('the reach', () {
    test('starts 28 days before the oldest Monday', () {
      expect(overallHistoryStart(monday), back(105));
      expect(overallHistoryStart(today), back(105));
    });

    test('on a Sunday it is 111 days back, not 105', () {
      const sunday = LocalDate(2026, 11, 15);

      expect(overallHistoryStart(sunday), const LocalDate(2026, 7, 27));
      expect(sunday.daysSince(overallHistoryStart(sunday)), 111);
    });
  });

  group('the weeks', () {
    test('are the last 12 Mondays, oldest first', () {
      final history = collect();

      expect(history.weeks, hasLength(12));
      expect(history.weeks.first.date, back(77));
      expect(history.current.date, monday);
      expect(history.weeks.every((w) => mondayOf(w.date) == w.date), isTrue);
    });

    test('the oldest Monday has its full window', () {
      final oldest = collect().weeks.first;

      expect(oldest.inputs.restingHeartRate, 52);
      expect(oldest.inputs.sleepHours, 8);
      expect(oldest.inputs.dailySteps, 8000);
      expect(oldest.result, isA<Scored<OverallFactor>>());
    });

    test('a Monday before there were 14 nights has no score', () {
      final history = collect(days: 20);

      expect(
        history.weeks.first.result,
        isA<InsufficientData<OverallFactor>>(),
      );
      expect(history.scored, isNotNull);
    });
  });

  group('the current week', () {
    test('scores without fitness and without body on 60 points', () {
      final history = collect();

      expect(history.current.inputs.coverage, 60);
      expect(history.scored!.missing, [
        OverallFactor.fitness,
        OverallFactor.body,
      ]);
      expect(history.current.inputs.weeklyMinutes, 210);
      expect(history.current.inputs.sleepRegularity, 100);
    });

    test('fitness is always missing', () {
      for (final week in collect().weeks) {
        expect(week.inputs.fitnessPercentile, isNull);
      }
    });

    test('60 years or more reads the steps of an older adult', () {
      expect(collect(birthYear: 1966).current.inputs.olderAdult, isTrue);
      expect(collect(birthYear: 1967).current.inputs.olderAdult, isFalse);
      expect(collect().current.inputs.olderAdult, isFalse);
    });

    test('strength days are counted per week', () {
      final history = collect(
        strengthDates: [back(2), back(5), back(9), back(12)],
      );

      expect(history.current.inputs.strengthPerWeek, 1);
    });
  });

  group('the first score', () {
    test('appears on the day the minimum is met, before the next Monday', () {
      // 12 nights by the Monday, 14 by Wednesday, today is Friday.
      final history = collect(days: 12, extra: 4);

      expect(history.weeks.last.result, isA<InsufficientData<OverallFactor>>());
      expect(history.current.date, monday.addDays(2));
      expect(history.scored, isNotNull);
      expect(history.previous, isNull);
    });

    test('without enough nights the week on screen is the last Monday', () {
      final history = collect(days: 5, extra: 4);

      expect(history.current.date, monday);
      expect(history.scored, isNull);
      expect(history.nights, 9);
    });

    test('a scored Monday is never replaced by a later day', () {
      expect(collect(extra: 4).current.date, monday);
    });
  });

  group('around the week on screen', () {
    test('the next update is the Monday after today', () {
      expect(collect().nextUpdate, monday.addDays(7));
    });

    test('previous is the score of the Monday before', () {
      final history = collect();

      expect(
        history.previous,
        (history.weeks[10].result as Scored<OverallFactor>).value,
      );
    });

    test('nights counts the last 28 days without the excluded ones', () {
      expect(collect(extra: 4).nights, 27);
      expect(
        collect(
          extra: 4,
          tags: {monday: DayTag.sick, back(1): DayTag.rest},
        ).nights,
        26,
      );
    });
  });

  group('tagged days', () {
    test('sick and travel leave the windows and rest stays', () {
      expect(
        overallExcluded({
          back(1): DayTag.sick,
          back(2): DayTag.travel,
          back(3): DayTag.rest,
        }),
        {back(1), back(2)},
      );
    });

    test('with 15 days sick the current week has no score', () {
      final history = collect(
        tags: {for (var age = 15; age >= 1; age--) back(age): DayTag.sick},
      );

      expect(history.scored, isNull);
      expect(history.current.inputs.restingHeartRate, isNull);
    });
  });

  group('body', () {
    test('without a height there is no body input', () {
      final history = collect(weighIns: [weighIn(back(3), 80, waist: 90)]);

      expect(history.current.inputs.waistToHeight, isNull);
      expect(history.current.inputs.bmi, isNull);
    });

    test('without weigh-ins there is no body input', () {
      final history = collect(heightCentimeters: 180);

      expect(history.current.inputs.waistToHeight, isNull);
      expect(history.current.inputs.bmi, isNull);
    });

    test('reads the last waist and the last weight before the Monday', () {
      final history = collect(
        heightCentimeters: 180,
        weighIns: [
          weighIn(back(20), 84, waist: 92),
          weighIn(back(3), 81),
          weighIn(monday, 60, waist: 60),
        ],
      );

      expect(history.current.inputs.waistToHeight, closeTo(92 / 180, 1e-9));
      expect(history.current.inputs.bmi, closeTo(81 / (1.8 * 1.8), 1e-9));
      expect(history.current.inputs.coverage, 70);
    });

    test('a past Monday does not read a later weigh-in', () {
      final history = collect(
        heightCentimeters: 180,
        weighIns: [weighIn(back(3), 81, waist: 90)],
      );

      expect(history.weeks[10].inputs.waistToHeight, isNull);
      expect(history.weeks[10].inputs.bmi, isNull);
    });
  });

  group('sleep sessions by source', () {
    test('keep the naps of the source that owns the date', () {
      final date = back(3);
      final main = span(date.addDays(-1), 23, const Duration(hours: 8));
      final nap = span(date, 14, const Duration(minutes: 40));
      final other = span(date.addDays(-1), 22, const Duration(hours: 9));
      final sessions = sessionsBySourcePriority(
        {
          'ring': [main, nap],
          'other': [other],
        },
        ['ring', 'other'],
      );

      expect(sessions, hasLength(2));
      expect([for (final s in sessions) s.start], [main.start, nap.start]);
    });

    test('a date the first source lacks takes the next source', () {
      final first = span(back(4), 23, const Duration(hours: 8));
      final second = span(back(2), 23, const Duration(hours: 8));
      final sessions = sessionsBySourcePriority(
        {
          'ring': [first],
          'other': [second, first],
        },
        ['ring', 'other'],
      );

      expect([for (final s in sessions) s.start], [first.start, second.start]);
    });
  });
}
