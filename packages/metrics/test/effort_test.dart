import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const hist = <double>[
  135, 0, 126, 15, 0, 104, 23, 150, 0, 120, 0, 23, 112, 0, 144, 23, 133, //
  0, 0, 0, 45, 158, 0, 128, 15, 0, 108, 23, 150, 0, 131, 23, 0, 45, 0,
];

List<double> histPlus(List<double> tail) => [...hist, ...tail];

Duration minutes(num value) => Duration(seconds: (value * 60).round());

Map<int, Duration> zones(List<int> perZone) => {
  for (var i = 0; i < perZone.length; i++) i + 1: Duration(minutes: perZone[i]),
};

CoachAdvice advise(
  List<double> load, {
  int? readiness = 80,
  bool sick = false,
}) => coachAdvice(readiness: readiness, sick: sick, dailyLoad: load);

DailyValue point(int month, int day, double value) =>
    (date: LocalDate(2026, month, day), value: value);

void main() {
  group('constants', () {
    test('the INTERFACE constants carry the spec values', () {
      expect(effortWeekPoints, 150);
      expect(effortWeekStrengthDays, 2);
      expect(effortStrengthMinMinutes, 20);
      expect(effortRatingDivisor, 2.0);
      expect(effortWalkingLoadFactor, 1.5);
      expect(effortAcuteDays, 7);
      expect(effortChronicDays, 28);
      expect(effortLineSeedDays, 7);
      expect(effortMinLoadDays, 14);
      expect(effortHardFloor, 120);
      expect(effortHardFactor, 1.5);
      expect(effortEasyFraction, 0.5);
      expect(effortHardRunDays, 2);
      expect(effortNoEasyDays, 6);
      expect(effortSpikeFactor, 1.5);
      expect(effortSpikeMinWeekly, 150.0);
      expect(effortMinRating, 1);
      expect(effortMaxRating, 10);
    });
  });

  group('criterion 1: the rating beats a lower heart rate figure', () {
    test('strength 45 min with rating 7 takes the rating, 157.5 rounds up', () {
      final load = sessionLoad(
        elapsed: const Duration(minutes: 45),
        typeDefault: 2.5,
        timeInZones: zones([14, 12, 6, 0, 0]),
        rating: 7,
      );

      expect(load.byHeartRate, 56);
      expect(load.byRating, 158);
      expect(load.byDefault, 113);
      expect(load.value, 158);
      expect(load.source, LoadSource.rating);
    });

    test('a default of 112.5 rounds up too', () {
      final load = sessionLoad(
        elapsed: const Duration(minutes: 45),
        typeDefault: 2.5,
      );

      expect(load.byDefault, 113);
    });
  });

  group('criterion 2: a higher heart rate figure beats the rating', () {
    test('run 40 min with rating 6 takes the heart rate', () {
      final load = sessionLoad(
        elapsed: const Duration(minutes: 40),
        typeDefault: 3,
        timeInZones: zones([2, 5, 14, 16, 3]),
        rating: 6,
      );

      expect(load.byHeartRate, 133);
      expect(load.byRating, 120);
      expect(load.value, 133);
      expect(load.source, LoadSource.heartRate);
    });
  });

  group('criterion 3: the rating is optional over a heart rate', () {
    final runZones = zones([2, 4, 12, 12, 2]);

    test('without a rating the value is the heart rate figure', () {
      final load = sessionLoad(
        elapsed: const Duration(minutes: 32),
        typeDefault: 3,
        timeInZones: runZones,
      );

      expect(load.value, 104);
      expect(load.source, LoadSource.heartRate);
      expect(load.byRating, isNull);
    });

    test('with rating 7 the rating is higher and wins', () {
      final load = sessionLoad(
        elapsed: const Duration(minutes: 32),
        typeDefault: 3,
        timeInZones: runZones,
        rating: 7,
      );

      expect(load.byRating, 112);
      expect(load.value, 112);
      expect(load.source, LoadSource.rating);
    });
  });

  group('criterion 4: no measurement falls back to the type default', () {
    test('no zones and no rating', () {
      final load = sessionLoad(
        elapsed: const Duration(minutes: 45),
        typeDefault: 2.5,
      );

      expect(load.value, 113);
      expect(load.source, LoadSource.typeDefault);
      expect(load.byHeartRate, isNull);
      expect(load.byRating, isNull);
    });

    test('zones that are all zero behave like no zones', () {
      final load = sessionLoad(
        elapsed: const Duration(minutes: 45),
        typeDefault: 2.5,
        timeInZones: {for (var z = 1; z <= 5; z++) z: Duration.zero},
      );

      expect(load.value, 113);
      expect(load.source, LoadSource.typeDefault);
      expect(load.byHeartRate, isNull);
    });

    test('a rating alone wins even when it is below the default', () {
      final load = sessionLoad(
        elapsed: const Duration(minutes: 45),
        typeDefault: 5,
        rating: 2,
      );

      expect(load.byRating, 45);
      expect(load.byDefault, 225);
      expect(load.value, 45);
      expect(load.source, LoadSource.rating);
    });

    test('minutes are taken from seconds', () {
      final load = sessionLoad(
        elapsed: const Duration(minutes: 1, seconds: 30),
        typeDefault: 2,
      );

      expect(load.byDefault, 3);
    });

    test('a zero length session has a zero load', () {
      final load = sessionLoad(elapsed: Duration.zero, typeDefault: 3);

      expect(load.value, 0);
      expect(load.source, LoadSource.typeDefault);
    });
  });

  group('criterion 5: a tie goes to the heart rate', () {
    test('20 min in zone 3 against rating 6 is 60 both ways', () {
      final load = sessionLoad(
        elapsed: const Duration(minutes: 20),
        typeDefault: 3,
        timeInZones: zones([0, 0, 20, 0, 0]),
        rating: 6,
      );

      expect(load.byHeartRate, 60);
      expect(load.byRating, 60);
      expect(load.value, 60);
      expect(load.source, LoadSource.heartRate);
    });
  });

  group('criterion 6: the rating range', () {
    SessionLoad rated(int rating) => sessionLoad(
      elapsed: const Duration(minutes: 30),
      typeDefault: 3,
      rating: rating,
    );

    test('0 and 11 throw', () {
      expect(() => rated(0), throwsArgumentError);
      expect(() => rated(11), throwsArgumentError);
    });

    test('1 and 10 do not', () {
      expect(rated(1).byRating, 15);
      expect(rated(10).byRating, 150);
    });
  });

  group('sessionLoad refuses bad input', () {
    test('a negative elapsed throws', () {
      expect(
        () => sessionLoad(elapsed: const Duration(seconds: -1), typeDefault: 3),
        throwsArgumentError,
      );
    });

    test('a negative, NaN or infinite type default throws', () {
      for (final bad in [-1.0, double.nan, double.infinity]) {
        expect(
          () => sessionLoad(
            elapsed: const Duration(minutes: 30),
            typeDefault: bad,
          ),
          throwsArgumentError,
          reason: '$bad',
        );
      }
    });
  });

  group('criterion 7: walkingLoad', () {
    test('15 brisk minutes are 22.5, which rounds to 23', () {
      expect(walkingLoad(15), 23);
    });

    test('zero minutes are zero', () {
      expect(walkingLoad(0), 0);
    });

    test('a negative or non finite figure throws', () {
      expect(() => walkingLoad(-1), throwsArgumentError);
      expect(() => walkingLoad(double.nan), throwsArgumentError);
      expect(() => walkingLoad(double.infinity), throwsArgumentError);
    });
  });

  group('criterion 8: isStrengthSession', () {
    test('19 min 59 s is not a strength session', () {
      expect(
        isStrengthSession(const Duration(minutes: 19, seconds: 59)),
        isFalse,
      );
    });

    test('20 min is', () {
      expect(isStrengthSession(const Duration(minutes: 20)), isTrue);
    });
  });

  group('criterion 9: loadLine', () {
    test('13 values give no line, 14 give one', () {
      expect(loadLine(List.filled(13, 40), days: 28), isNull);
      expect(loadLine(List.filled(14, 40), days: 28), closeTo(40, 1e-9));
    });

    test('an empty list gives no line', () {
      expect(loadLine(const [], days: 7), isNull);
    });

    test('the 28 day line through HIST plus three days', () {
      expect(
        loadLine(histPlus([158, 0, 133]), days: 28),
        closeTo(59.568, 0.001),
      );
    });

    test('the 28 and 7 day lines through HIST plus four days', () {
      final series = histPlus([158, 0, 133, 23]);

      expect(loadLine(series, days: 28), closeTo(57.046, 0.001));
      expect(loadLine(series, days: 7), closeTo(58.271, 0.001));
    });

    test('a line of zeros stays at zero', () {
      expect(loadLine(List.filled(28, 0), days: 28), 0);
    });

    test('days under 1 throws', () {
      expect(() => loadLine(hist, days: 0), throwsArgumentError);
      expect(() => loadLine(hist, days: -3), throwsArgumentError);
    });
  });

  group('criterion 10: hardDayFrom', () {
    test('a line of 57 is under the floor of 120', () {
      expect(hardDayFrom(57), 120);
    });

    test('a line of 100 gives 150', () {
      expect(hardDayFrom(100), 150);
    });

    test('a line of zero gives the floor', () {
      expect(hardDayFrom(0), 120);
    });

    test('1.5 times 81 is 121.5 and rounds up to 122', () {
      expect(hardDayFrom(81), 122);
      expect(hardDayFrom(80), 120);
    });
  });

  group('criterion 11: effortWeek', () {
    const today = LocalDate(2026, 11, 13);
    final points = [
      point(11, 7, 30),
      point(11, 9, 45),
      point(11, 11, 80),
      point(11, 12, 15),
    ];

    test('the Friday week from Monday 11-09 sums to 140', () {
      final week = effortWeek(points, {
        const LocalDate(2026, 11, 9),
      }, today: today);

      expect(week.monday, const LocalDate(2026, 11, 9));
      expect(week.points, 140);
      expect(week.strengthDays, 1);
      expect(week.covered, isFalse);
    });

    test(
      'weeklyIntensityMinutes of the same data stays 170 (already true)',
      () {
        final withZeros = [
          ...points,
          point(11, 8, 0),
          point(11, 10, 0),
          point(11, 13, 0),
        ];

        expect(
          weeklyIntensityMinutes(withZeros, today: today, minDays: 4),
          170,
        );
      },
    );

    test('no data is zero points and not covered', () {
      final week = effortWeek(const [], const {}, today: today);

      expect(week.points, 0);
      expect(week.strengthDays, 0);
      expect(week.covered, isFalse);
    });

    test('a later value for the same date replaces the earlier one', () {
      final week = effortWeek(
        [point(11, 10, 50), point(11, 10, 20)],
        const {},
        today: today,
      );

      expect(week.points, 20);
    });

    test('values after today and before Monday are left out', () {
      final week = effortWeek(
        [
          point(11, 8, 99),
          point(11, 9, 10),
          point(11, 13, 5),
          point(11, 14, 70),
        ],
        const {},
        today: today,
      );

      expect(week.points, 15);
    });

    test('a negative or non finite value is ignored', () {
      final week = effortWeek(
        [
          point(11, 9, 10),
          point(11, 10, -5),
          point(11, 11, double.nan),
          point(11, 12, double.infinity),
        ],
        const {},
        today: today,
      );

      expect(week.points, 10);
    });

    test('on a Monday the week is that one day', () {
      final week = effortWeek(
        [point(11, 8, 40), point(11, 9, 25)],
        const {},
        today: const LocalDate(2026, 11, 9),
      );

      expect(week.monday, const LocalDate(2026, 11, 9));
      expect(week.points, 25);
    });

    test('on a Sunday the week still starts on the Monday before', () {
      final week = effortWeek(
        [point(11, 9, 25), point(11, 15, 5)],
        const {},
        today: const LocalDate(2026, 11, 15),
      );

      expect(week.monday, const LocalDate(2026, 11, 9));
      expect(week.points, 30);
    });
  });

  group('criterion 12: effortWeek covered', () {
    const today = LocalDate(2026, 11, 13);
    const twoDays = {LocalDate(2026, 11, 9), LocalDate(2026, 11, 11)};

    bool covered(double total, Set<LocalDate> strength) =>
        effortWeek([point(11, 10, total)], strength, today: today).covered;

    test('150 points and 2 strength days is covered', () {
      expect(covered(150, twoDays), isTrue);
    });

    test('149 points and 2 strength days is not', () {
      expect(covered(149, twoDays), isFalse);
    });

    test('300 points and 1 strength day is not', () {
      expect(covered(300, {const LocalDate(2026, 11, 9)}), isFalse);
    });

    test('a strength day next week or last week does not count', () {
      final week = effortWeek(
        [point(11, 10, 200)],
        {
          const LocalDate(2026, 11, 9),
          const LocalDate(2026, 11, 8),
          const LocalDate(2026, 11, 14),
          const LocalDate(2026, 11, 16),
        },
        today: today,
      );

      expect(week.strengthDays, 1);
      expect(week.covered, isFalse);
    });
  });

  group('criterion 13: lowReadiness', () {
    test('Tuesday readiness 52 recovers', () {
      final advice = advise(histPlus([158]), readiness: 52);

      expect(advice.rule, CoachRule.lowReadiness);
      expect(advice.rule.number, 2);
      expect(advice.rule.verdict, CoachVerdict.recover);
    });
  });

  group('criterion 14: hardYesterday', () {
    test('Thursday readiness 74 after a hard 133', () {
      final advice = advise(histPlus([158, 0, 133]), readiness: 74);

      expect(advice.rule, CoachRule.hardYesterday);
      expect(advice.rule.number, 7);
      expect(advice.rule.verdict, CoachVerdict.maintain);
      expect(advice.chronic, closeTo(59.568, 0.001));
      expect(advice.hardFrom, 120);
      expect(advice.yesterdayLoad, 133);
      expect(advice.hardDays, 1);
    });
  });

  group('criterion 15: goodReadiness', () {
    test('Friday readiness 78 after an easy 23', () {
      final advice = advise(histPlus([158, 0, 133, 23]), readiness: 78);

      expect(advice.rule, CoachRule.goodReadiness);
      expect(advice.rule.number, 8);
      expect(advice.rule.verdict, CoachVerdict.push);
      expect(advice.chronic, closeTo(57.046, 0.001));
      expect(advice.acute, closeTo(58.271, 0.001));
      expect(advice.hardDays, 0);
    });
  });

  group('criterion 16: under 14 days of load', () {
    test('13 days give no lines, no threshold and no counts', () {
      final advice = advise(List.filled(13, 40));

      expect(advice.rule, CoachRule.goodReadiness);
      expect(advice.acute, isNull);
      expect(advice.chronic, isNull);
      expect(advice.hardFrom, isNull);
      expect(advice.hardDays, 0);
      expect(advice.daysSinceEasy, 0);
    });

    test('an empty list has no yesterday', () {
      final advice = advise(const []);

      expect(advice.yesterdayLoad, isNull);
      expect(advice.rule, CoachRule.goodReadiness);
    });

    test('series of 7 and 8 days have no line at all', () {
      for (final length in [7, 8]) {
        final advice = advise(List.filled(length, 40));

        expect(advice.acute, isNull, reason: '$length');
        expect(advice.chronic, isNull, reason: '$length');
        expect(advice.chronicWeekAgo, isNull, reason: '$length');
        expect(advice.hardFrom, isNull, reason: '$length');
        expect(advice.yesterdayLoad, 40, reason: '$length');
        expect(advice.rule, CoachRule.goodReadiness, reason: '$length');
      }
    });

    test('14 days give the lines but no threshold and no week ago line', () {
      final advice = advise(List.filled(14, 40));

      expect(advice.acute, closeTo(40, 1e-9));
      expect(advice.chronic, closeTo(40, 1e-9));
      expect(advice.chronicWeekAgo, isNull);
      expect(advice.hardFrom, isNull);
      expect(advice.hardDays, 0);
    });

    test('15 days give the threshold but still no week ago line', () {
      final advice = advise([...List.filled(14, 40), 200]);

      expect(advice.chronicWeekAgo, isNull);
      expect(advice.hardFrom, 120);
      expect(advice.hardDays, 1);
      expect(advice.chronic, closeTo(51.034, 0.001));
      expect(advice.acute, closeTo(80, 0.001));
    });

    test('21 days give the week ago line', () {
      final advice = advise(List.filled(21, 40));

      expect(advice.chronicWeekAgo, closeTo(40, 1e-9));
      expect(advice.hardFrom, 120);
    });
  });

  group('criterion 17: no readiness', () {
    test('after an easy day the rule is noReadiness', () {
      final advice = advise(histPlus([158, 0, 133, 23]), readiness: null);

      expect(advice.rule, CoachRule.noReadiness);
      expect(advice.rule.number, 9);
      expect(advice.rule.verdict, CoachVerdict.maintain);
    });

    test('after a hard day the rule is hardYesterday', () {
      final advice = advise(histPlus([158, 0, 133]), readiness: null);

      expect(advice.rule, CoachRule.hardYesterday);
    });

    test('rules 3 and 4 still fire without a readiness', () {
      expect(
        advise([...List.filled(20, 40), 200, 200], readiness: null).rule,
        CoachRule.hardRun,
      );
      expect(
        advise(List.filled(30, 60), readiness: null).rule,
        CoachRule.noEasyDay,
      );
    });
  });

  group('criterion 18: sick', () {
    test('sick wins over a readiness of 90', () {
      final advice = advise(
        histPlus([158, 0, 133, 23]),
        readiness: 90,
        sick: true,
      );

      expect(advice.rule, CoachRule.sick);
      expect(advice.rule.number, 1);
      expect(advice.rule.verdict, CoachVerdict.recover);
    });

    test('sick wins over a hard run and a missing readiness', () {
      final load = [...List.filled(20, 40), 200, 200];

      expect(advise(load, readiness: null, sick: true).rule, CoachRule.sick);
      expect(advise(load, readiness: 40, sick: true).rule, CoachRule.sick);
    });
  });

  group('criterion 19: a chronic line of zero', () {
    test('28 zeros never fire noEasyDay', () {
      final advice = advise(List.filled(28, 0));

      expect(advice.rule, CoachRule.goodReadiness);
      expect(advice.daysSinceEasy, 0);
      expect(advice.chronic, 0);
      expect(advice.hardFrom, 120);
    });

    test('after zeros, a load of 120 is hard and 119 is not', () {
      final hard = advise([...List.filled(20, 0), 120]);
      final notHard = advise([...List.filled(20, 0), 119]);

      expect(hard.hardFrom, 120);
      expect(hard.hardDays, 1);
      expect(hard.rule, CoachRule.hardYesterday);
      expect(notHard.hardDays, 0);
      expect(notHard.rule, CoachRule.goodReadiness);
    });
  });

  group('criterion 20: hardRun', () {
    test('two hard days in a row recover', () {
      final advice = advise([...List.filled(20, 40), 200, 200]);

      expect(advice.rule, CoachRule.hardRun);
      expect(advice.rule.number, 3);
      expect(advice.rule.verdict, CoachVerdict.recover);
      expect(advice.hardDays, 2);
    });

    test('hardRun beats a fair readiness and loses to a low one', () {
      final load = [...List.filled(20, 40), 200, 200];

      expect(advise(load, readiness: 60).rule, CoachRule.hardRun);
      expect(advise(load, readiness: 50).rule, CoachRule.lowReadiness);
    });

    test('the hard test uses the line through the day before', () {
      final advice = advise([...List.filled(20, 100), 150]);

      expect(advice.hardFrom, 150);
      expect(advice.hardDays, 1);
    });

    test('a load one under the threshold is not hard', () {
      final advice = advise([...List.filled(20, 100), 149]);

      expect(advice.hardFrom, 150);
      expect(advice.hardDays, 0);
    });

    test('the run of hard days is counted back from yesterday only', () {
      final advice = advise([...List.filled(20, 40), 200, 0, 200]);

      expect(advice.hardDays, 1);
    });
  });

  group('criterion 21: noEasyDay', () {
    test('30 days of 60 recover with 28 days since an easy one', () {
      final advice = advise(List.filled(30, 60));

      expect(advice.rule, CoachRule.noEasyDay);
      expect(advice.rule.number, 4);
      expect(advice.rule.verdict, CoachVerdict.recover);
      expect(advice.daysSinceEasy, 28);
    });

    test('five days since an easy day does not fire, six does', () {
      final five = advise([...List.filled(20, 40), 5, 40, 40, 40, 40, 40]);
      final six = advise([...List.filled(20, 40), 5, 40, 40, 40, 40, 40, 40]);

      expect(five.daysSinceEasy, 5);
      expect(five.rule, CoachRule.goodReadiness);
      expect(six.daysSinceEasy, 6);
      expect(six.rule, CoachRule.noEasyDay);
    });
  });

  group('criterion 22: spike', () {
    final base = [
      for (var i = 0; i < 14; i++) ...[100.0, 0.0],
    ];
    final spikeSeries = [...base, 110, 110, 110, 0, 110, 110, 110];

    test('a jump over 1.5 times the line of a week ago maintains', () {
      final advice = advise(spikeSeries);

      expect(advice.rule, CoachRule.spike);
      expect(advice.rule.number, 6);
      expect(advice.rule.verdict, CoachVerdict.maintain);
      expect(advice.acute, closeTo(89.436, 0.001));
      expect(advice.chronicWeekAgo, closeTo(49.409, 0.001));
      expect(advice.hardDays, 0);
      expect(advice.daysSinceEasy, 3);
    });

    test('a fair readiness is answered before the spike', () {
      expect(advise(spikeSeries, readiness: 65).rule, CoachRule.fairReadiness);
    });

    test('a week ago line under 150 a week does not spike', () {
      final quiet = [
        ...List.filled(14, 20),
        ...List.filled(7, 20),
        ...List.filled(3, 100),
        0,
        ...List.filled(3, 100),
      ];
      final advice = advise(quiet);

      expect(advice.chronicWeekAgo! * 7, lessThan(150));
      expect(advice.acute!, greaterThan(1.5 * advice.chronicWeekAgo!));
      expect(advice.rule, isNot(CoachRule.spike));
    });
  });

  group('criterion 23: readiness thresholds', () {
    final calm = histPlus([158, 0, 133, 23]);

    test('60 is fair', () {
      final advice = advise(calm, readiness: 60);

      expect(advice.rule, CoachRule.fairReadiness);
      expect(advice.rule.number, 5);
      expect(advice.rule.verdict, CoachVerdict.maintain);
    });

    test('54 is low, 55 is fair, 69 is fair, 70 is good', () {
      expect(advise(calm, readiness: 54).rule, CoachRule.lowReadiness);
      expect(advise(calm, readiness: 55).rule, CoachRule.fairReadiness);
      expect(advise(calm, readiness: 69).rule, CoachRule.fairReadiness);
      expect(advise(calm, readiness: 70).rule, CoachRule.goodReadiness);
    });

    test('the bounds 0 and 100 are valid', () {
      expect(advise(calm, readiness: 0).rule, CoachRule.lowReadiness);
      expect(advise(calm, readiness: 100).rule, CoachRule.goodReadiness);
    });
  });

  group('criterion 24: readiness out of range', () {
    test('-1 and 101 throw', () {
      expect(() => advise(hist, readiness: -1), throwsArgumentError);
      expect(() => advise(hist, readiness: 101), throwsArgumentError);
    });
  });

  group('criterion 25: the rule table', () {
    const table = {
      CoachRule.sick: (1, CoachVerdict.recover),
      CoachRule.lowReadiness: (2, CoachVerdict.recover),
      CoachRule.hardRun: (3, CoachVerdict.recover),
      CoachRule.noEasyDay: (4, CoachVerdict.recover),
      CoachRule.fairReadiness: (5, CoachVerdict.maintain),
      CoachRule.spike: (6, CoachVerdict.maintain),
      CoachRule.hardYesterday: (7, CoachVerdict.maintain),
      CoachRule.goodReadiness: (8, CoachVerdict.push),
      CoachRule.noReadiness: (9, CoachVerdict.maintain),
    };

    test('there are nine rules, in order', () {
      expect(CoachRule.values, table.keys.toList());
    });

    test('each number is its index plus 1 and each verdict is as listed', () {
      for (final rule in CoachRule.values) {
        expect(rule.number, rule.index + 1, reason: '$rule');
        expect(rule.number, table[rule]!.$1, reason: '$rule');
        expect(rule.verdict, table[rule]!.$2, reason: '$rule');
      }
    });
  });
}
