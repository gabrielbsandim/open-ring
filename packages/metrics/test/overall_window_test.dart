import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const monday = LocalDate(2026, 11, 9);

LocalDate back(int days) => monday.addDays(-days);

SleepNight night(LocalDate date, {double hours = 7}) {
  final end = DateTime.utc(date.year, date.month, date.day, 7);
  return SleepNight([
    SleepSpan(
      start: end.subtract(Duration(minutes: (hours * 60).round())),
      end: end,
      phase: SleepPhase.light,
      utcOffset: Duration.zero,
    ),
  ]);
}

List<DailyValue> daily(int from, int to, double value) => [
  for (var age = from; age >= to; age--) (date: back(age), value: value),
];

Set<LocalDate> days(int from, int to) => {
  for (var age = from; age >= to; age--) back(age),
};

OverallInputs collect({
  List<SleepNight>? nights,
  Set<LocalDate>? wornDays,
  Set<LocalDate> excluded = const {},
  List<DailyValue>? resting,
  List<DailyValue>? steps,
  List<DailyValue>? intensity,
  List<LocalDate> strengthDates = const [],
  double? waistToHeight,
  double? bmi,
}) {
  final allNights =
      nights ?? [for (var age = 28; age >= 1; age--) night(back(age))];
  return overallInputsOn(
    monday,
    nights: allNights,
    spans: [for (final n in allNights) ...n.spans],
    wornDays: wornDays ?? days(28, 1),
    excluded: excluded,
    resting: resting ?? daily(28, 1, 54),
    steps: steps ?? daily(28, 1, 7000),
    intensity: intensity ?? daily(28, 1, 20),
    strengthDates: strengthDates,
    waistToHeight: waistToHeight,
    bmi: bmi,
  );
}

void main() {
  group('the Mondays', () {
    test('are 12, oldest first, ending at the last Monday', () {
      final mondays = overallMondays(const LocalDate(2026, 11, 13));

      expect(mondays, hasLength(12));
      expect(mondays.last, monday);
      expect(mondays.first, back(77));
      expect(mondays.every((d) => mondayOf(d) == d), isTrue);
    });

    test('a Monday is its own last Monday', () {
      expect(overallMondays(monday).last, monday);
    });
  });

  group('the window', () {
    test('is the 28 days that end the day before the Monday', () {
      final inputs = collect(
        resting: [
          ...daily(28, 1, 50),
          (date: monday, value: 90),
          (date: back(29), value: 90),
        ],
      );

      expect(inputs.restingHeartRate, 50);
    });

    test('13 nights give no sleep input and 14 give the mean', () {
      final thirteen = collect(
        nights: [for (var age = 13; age >= 1; age--) night(back(age))],
      );
      final fourteen = collect(
        nights: [
          for (var age = 14; age >= 1; age--)
            night(back(age), hours: age.isEven ? 6 : 8),
        ],
      );

      expect(thirteen.sleepHours, isNull);
      expect(fourteen.sleepHours, closeTo(7, 1e-9));
    });

    test('an excluded day leaves every window', () {
      final excluded = days(28, 15);
      final inputs = collect(
        excluded: excluded,
        resting: [...daily(28, 15, 80), ...daily(14, 1, 50)],
        steps: [...daily(28, 15, 0), ...daily(14, 1, 8000)],
        intensity: [...daily(28, 15, 0), ...daily(14, 1, 30)],
        strengthDates: [back(20), back(3), back(10)],
      );

      expect(inputs.restingHeartRate, 50);
      expect(inputs.dailySteps, 8000);
      expect(inputs.weeklyMinutes, 210);
      expect(inputs.strengthPerWeek, 1);
      expect(inputs.sleepHours, 7);
    });

    test('with 15 days excluded nothing has enough days', () {
      final inputs = collect(excluded: days(28, 14));

      expect(inputs.restingHeartRate, isNull);
      expect(inputs.sleepHours, isNull);
      expect(inputs.dailySteps, isNull);
      expect(inputs.weeklyMinutes, isNull);
      expect(inputs.sleepRegularity, isNull);
      expect(inputs.strengthPerWeek, 0);
    });
  });

  group('movement', () {
    test('minutes are the weekly rate over the worn days', () {
      expect(collect().weeklyMinutes, 140);
      expect(
        collect(
          wornDays: days(14, 1),
          intensity: daily(14, 1, 30),
        ).weeklyMinutes,
        210,
      );
    });

    test('a worn day without steps or minutes counts as zero', () {
      final inputs = collect(
        steps: daily(14, 1, 8000),
        intensity: daily(14, 1, 40),
      );

      expect(inputs.dailySteps, 4000);
      expect(inputs.weeklyMinutes, 140);
    });

    test('a day the ring was not worn is left out of steps', () {
      final inputs = collect(
        wornDays: days(14, 1),
        steps: [...daily(28, 15, 200), ...daily(14, 1, 8000)],
      );

      expect(inputs.dailySteps, 8000);
    });

    test('with 13 worn days steps and minutes are missing', () {
      final inputs = collect(wornDays: days(13, 1));

      expect(inputs.dailySteps, isNull);
      expect(inputs.weeklyMinutes, isNull);
      expect(inputs.sleepRegularity, isNull);
    });

    test('strength counts days, not sessions, over the whole window', () {
      final inputs = collect(
        strengthDates: [
          back(2),
          back(2),
          back(9),
          back(16),
          back(23),
          back(40),
        ],
      );

      expect(inputs.strengthPerWeek, 1);
    });
  });

  group('sleep regularity', () {
    test('identical nights give 100', () {
      expect(collect().sleepRegularity, 100);
    });

    test('a nap changes it', () {
      final nights = [for (var age = 28; age >= 1; age--) night(back(age))];
      final nap = SleepSpan(
        start: DateTime.utc(2026, 11, 3, 14),
        end: DateTime.utc(2026, 11, 3, 15),
        phase: SleepPhase.light,
        utcOffset: Duration.zero,
      );
      final inputs = overallInputsOn(
        monday,
        nights: nights,
        spans: [for (final n in nights) ...n.spans, nap],
        wornDays: days(28, 1),
        excluded: const {},
        resting: const [],
        steps: const [],
        intensity: const [],
        strengthDates: const [],
      );

      expect(inputs.sleepRegularity, lessThan(100));
    });
  });

  test('fitness and body are passed through', () {
    final inputs = collect(waistToHeight: 0.48, bmi: 24);

    expect(inputs.fitnessPercentile, isNull);
    expect(inputs.waistToHeight, 0.48);
    expect(inputs.bmi, 24);
    expect(collect().waistToHeight, isNull);
  });

  test('a full window without fitness or body scores on 60 points', () {
    final inputs = collect();

    expect(inputs.coverage, 60);
    expect(inputs.score, isA<Scored<OverallFactor>>());
  });
}
