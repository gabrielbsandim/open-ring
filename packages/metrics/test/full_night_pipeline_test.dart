import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

import 'synthetic_nights.dart';

const today = LocalDate(2026, 11, 10);
const eps = 1e-3;

Scored<F> scored<F extends Enum>(ScoreResult<F> result) => result as Scored<F>;

Duration minutes(int value) => Duration(minutes: value);

const historyHrv = [52, 48, 55, 50, 47, 53, 49];
const historyHeartRateShift = [0, 1, -1, 2, 0, -1, 1];

List<SyntheticNight> history(
  LocalDate today, {
  int nights = baselineMinDays,
  SyntheticZone zone = saoPaulo,
}) {
  final skip = historyHrv.length - nights;
  return [
    for (var i = skip; i < historyHrv.length; i++)
      referenceNight(
        wake: today.addDays(i - historyHrv.length),
        zone: zone,
        hrvBase: historyHrv[i],
        heartRateShift: historyHeartRateShift[i],
      ),
  ];
}

List<DailyValue> nightly(
  List<SyntheticNight> nights,
  double? Function(NightReport report) measure,
) {
  final values = <DailyValue>[];
  for (final data in nights) {
    final date = stitchSleep(data.spans).single.date;
    final value = measure(data.report(date));
    if (value == null) continue;
    values.add((date: date, value: value));
  }
  return values;
}

void main() {
  group('reference night through the whole pipeline', () {
    final data = referenceNight(wake: today, zone: saoPaulo);
    final report = data.report(today);
    final night = report.night!;

    test('a ring record crossing local midnight is one night on the wake '
        'date', () {
      expect(stitchSleep(data.spans), hasLength(1));
      expect(data.spans, hasLength(referencePeriods.length));
      expect(night.start, DateTime.utc(2026, 11, 10, 2, 7));
      expect(night.end, DateTime.utc(2026, 11, 10, 10, 7));
      expect(night.date, today);
    });

    test('measures the night', () {
      expect(night.timeInBed, minutes(480));
      expect(night.asleep, minutes(396));
      expect(night.awake, minutes(84));
      expect(night.latency, minutes(42));
      expect(night.efficiency, closeTo(0.825, 1e-12));
      expect(night.timeIn(SleepPhase.light), minutes(284));
      expect(night.timeIn(SleepPhase.deep), minutes(52));
      expect(night.timeIn(SleepPhase.rem), minutes(60));
      expect(night.awakenings, hasLength(2));
      expect(night.wakeAfterSleepOnset, minutes(30));
      expect(night.gaps, isEmpty);
    });

    test('scores it as docs/metrics.md section 2 says', () {
      final score = scored(report.sleep);
      expect(score.of(SleepFactor.duration)!.points, closeTo(28.875, eps));
      expect(score.of(SleepFactor.efficiency)!.points, closeTo(17.5, eps));
      expect(score.of(SleepFactor.latency)!.points, closeTo(6, eps));
      expect(score.of(SleepFactor.deep)!.points, closeTo(17.5084, eps));
      expect(score.of(SleepFactor.rem)!.points, closeTo(11.3636, eps));
      expect(score.total, closeTo(81.2471, eps));
      expect(score.value, 81);
    });

    test('a ring that cannot report REM drops the factor and rescales', () {
      final noRem = referenceNight(
        wake: today,
        zone: saoPaulo,
        periods: withoutRem(referencePeriods),
      ).report(today, remMeasured: false);
      final score = scored(noRem.sleep);
      expect(score.of(SleepFactor.rem), isNull);
      expect(score.of(SleepFactor.duration)!.points, closeTo(33.9706, eps));
      expect(score.total, closeTo(82.2158, eps));
      expect(score.value, 82);
    });

    test('resting heart rate is the lowest 30 minutes of 5 minute slots', () {
      expect(data.heartRate.where((s) => during(s.at, night)), hasLength(96));
      expect(report.restingHeartRate, closeTo(51.6667, eps));
    });

    test('a low run outside the night does not reach resting heart rate', () {
      final evening = saoPaulo.instantOf(today.addDays(-1), 19 * 60);
      final withArtefact = referenceNight(
        wake: today,
        zone: saoPaulo,
        heartRateOverride: (at) =>
            at.isBefore(evening) || !at.isBefore(evening.add(minutes(30)))
            ? null
            : 44,
      );
      expect(restingHeartRate(withArtefact.heartRate), closeTo(44, eps));
      expect(
        withArtefact.report(today).restingHeartRate,
        closeTo(51.6667, eps),
      );
    });

    test('HRV is the mean of the 30 minute slots inside the night', () {
      expect(data.hrv.where((r) => during(r.at, night)), hasLength(16));
      expect(report.hrv, closeTo(50, 1e-9));
    });

    test('SpO2 keeps plausible hourly readings inside the night', () {
      final spo2 = report.spo2!;
      expect(spo2.readings, 8);
      expect(spo2.min, 88);
      expect(spo2.mean, closeTo(94, 1e-9));
      expect(spo2.readingsBelow, 2);
      expect(spo2.timeBelow, const Duration(hours: 2));
      expect(spo2.shareBelow, closeTo(0.25, 1e-9));
    });

    test('stress summarises the 30 minute slots of the date', () {
      const levels = [12, 18, 22, 30, 35, 48, 55, 62, 70, 80];
      final midnight = saoPaulo.instantOf(today, 0);
      final readings = <StressReading>[
        for (var slot = 0; slot < 48; slot++)
          (
            at: midnight.add(stressSlot * slot),
            level: slot < 30 ? levels[slot % levels.length] : 0,
          ),
      ];
      final summary = stressDaySummary(readings)!;
      expect(summary.readings, 30);
      expect(summary.mean, closeTo(43.2, 1e-9));
      expect(summary.min, 12);
      expect(summary.max, 80);
      expect(summary.timeInBand, {
        StressBand.rest: minutes(270),
        StressBand.low: minutes(270),
        StressBand.medium: minutes(270),
        StressBand.high: minutes(90),
      });
    });

    test('the fixture is deterministic', () {
      final again = referenceNight(wake: today, zone: saoPaulo);
      expect(again.heartRate, data.heartRate);
      expect(again.hrv, data.hrv);
      expect(again.spo2, data.spo2);
    });
  });

  group('the same wall clock night in other zones', () {
    final zones = {
      'Kiritimati': const SyntheticZone(Duration(hours: 14)),
      'Berlin': const SyntheticZone(Duration(hours: 1)),
      'Sao Paulo': saoPaulo,
      'Honolulu': const SyntheticZone(Duration(hours: -10)),
    };

    for (final MapEntry(key: name, value: zone) in zones.entries) {
      test('$name: same date and same score', () {
        final report = referenceNight(wake: today, zone: zone).report(today);
        expect(report.night!.date, today);
        expect(scored(report.sleep).value, 81);
        expect(report.restingHeartRate, closeTo(51.6667, eps));
        expect(report.hrv, closeTo(50, 1e-9));
      });
    }
  });

  group('daylight saving', () {
    const fallBackWake = LocalDate(2026, 10, 25);
    const springWake = LocalDate(2026, 3, 8);

    test('fall back: 8 h 30 elapsed between 23:30 and 07:00', () {
      final data = referenceNight(
        wake: fallBackWake,
        zone: berlinFallBack,
        startMinute: 1410,
        endMinute: 420,
        periods: const [
          (ringAwake, 10),
          (ringLight, 60),
          (ringDeep, 55),
          (ringLight, 50),
          (ringRem, 35),
          (ringLight, 70),
          (ringDeep, 40),
          (ringRem, 45),
          (ringLight, 80),
          (ringAwake, 5),
          (ringLight, 40),
          (ringRem, 20),
        ],
      );
      final report = data.report(fallBackWake);
      final night = report.night!;
      expect(night.start, DateTime.utc(2026, 10, 24, 21, 30));
      expect(night.end, DateTime.utc(2026, 10, 25, 6));
      expect(night.timeInBed, minutes(510));
      expect(night.asleep, minutes(495));
      expect(night.date, fallBackWake);
      expect(night.spans.first.utcOffset, const Duration(hours: 2));
      expect(night.spans.last.utcOffset, const Duration(hours: 1));
      expect(
        night.end.add(night.spans.last.utcOffset),
        DateTime.utc(2026, 10, 25, 7),
      );
      expect(data.heartRate.where((s) => during(s.at, night)), hasLength(102));
      expect(report.restingHeartRate, closeTo(51.6667, eps));
      expect(scored(report.sleep).value, 100);
    });

    test('spring forward: 7 h elapsed between 23:00 and 07:00', () {
      final data = referenceNight(
        wake: springWake,
        zone: newYorkSpringForward,
        startMinute: 1380,
        endMinute: 420,
        periods: const [
          (ringAwake, 5),
          (ringLight, 70),
          (ringDeep, 60),
          (ringLight, 60),
          (ringRem, 40),
          (ringDeep, 30),
          (ringLight, 70),
          (ringRem, 30),
          (ringLight, 45),
          (ringAwake, 10),
        ],
      );
      final report = data.report(springWake);
      final night = report.night!;
      expect(night.timeInBed, minutes(420));
      expect(night.asleep, minutes(405));
      expect(night.date, springWake);
      expect(data.heartRate.where((s) => during(s.at, night)), hasLength(84));
      expect(
        scored(report.sleep).of(SleepFactor.duration)!.points,
        closeTo(29.5312, eps),
      );
      expect(scored(report.sleep).value, 92);
    });

    test('the date comes from the offset at wake, not the one at bedtime', () {
      final flight = SyntheticZone(
        const Duration(hours: 9),
        changeAt: DateTime.utc(2026, 11, 9, 18),
        after: const Duration(hours: -5),
      );
      final night = stitchSleep(
        ringSleepSpans(
          wake: today,
          startMinute: referenceStartMinute,
          endMinute: referenceEndMinute,
          periods: referencePeriods,
          zone: flight,
        ),
      ).single;
      expect(night.end, DateTime.utc(2026, 11, 9, 22, 7));
      expect(night.spans.first.utcOffset, const Duration(hours: 9));
      expect(night.spans.last.utcOffset, const Duration(hours: -5));
      expect(night.date, const LocalDate(2026, 11, 9));
    });

    test('a baseline run across the change still has one value per date', () {
      const after = LocalDate(2026, 10, 28);
      final nights = history(after, zone: berlinFallBack);
      final hrv = nightly(nights, (r) => r.hrv);
      expect(hrv.map((d) => d.date), [
        for (var i = 7; i >= 1; i--) after.addDays(-i),
      ]);
      final baseline = hrvBaseline(hrv, today: after) as BaselineReady;
      expect(baseline.days, 7);
      expect(baseline.typical, closeTo(50.5018, eps));
    });
  });

  group('fragmented night', () {
    test('a no data stretch inside a record is a gap, counted as awake', () {
      final report = referenceNight(
        wake: today,
        zone: saoPaulo,
        periods: const [
          (ringAwake, 10),
          (ringLight, 90),
          (ringDeep, 40),
          (ringRem, 40),
          (ringNoData, 45),
          (ringLight, 80),
          (ringDeep, 30),
          (ringRem, 40),
          (ringLight, 105),
        ],
      ).report(today);
      final night = report.night!;
      expect(night.gaps.single.duration, minutes(45));
      expect(night.awakenings.single.bridgesGap, isTrue);
      expect(night.awakenings.single.duration, minutes(45));
      expect(night.timeInBed, minutes(480));
      expect(night.asleep, minutes(425));
      expect(scored(report.sleep).total, closeTo(95.1072, eps));
    });

    test('ring error codes are gaps too', () {
      final night = referenceNight(
        wake: today,
        zone: saoPaulo,
        periods: const [
          (ringLight, 120),
          (ringError, 30),
          (ringLight, 255),
          (ringLight, 75),
        ],
      ).report(today).night!;
      expect(night.gaps.single.duration, minutes(30));
      expect(night.timeInBed, minutes(480));
      expect(night.asleep, minutes(450));
    });

    test('a long wake logged as awake stays one night', () {
      final report = referenceNight(
        wake: today,
        zone: saoPaulo,
        endMinute: 487,
        periods: const [
          (ringAwake, 10),
          (ringLight, 100),
          (ringDeep, 40),
          (ringRem, 40),
          (ringAwake, 90),
          (ringLight, 80),
          (ringDeep, 30),
          (ringRem, 40),
          (ringLight, 110),
        ],
      ).report(today);
      final night = report.night!;
      expect(night.timeInBed, minutes(540));
      expect(night.asleep, minutes(440));
      expect(night.gaps, isEmpty);
      expect(night.awakenings.single.duration, minutes(90));
      expect(night.awakenings.single.bridgesGap, isFalse);
      expect(night.wakeAfterSleepOnset, minutes(90));
      expect(scored(report.sleep).value, 92);
    });

    test('a gap over 60 minutes splits it and only the longer part counts', () {
      final data = referenceNight(
        wake: today,
        zone: saoPaulo,
        endMinute: 457,
        periods: const [
          (ringLight, 60),
          (ringDeep, 40),
          (ringLight, 50),
          (ringNoData, 90),
          (ringLight, 100),
          (ringDeep, 50),
          (ringRem, 60),
          (ringLight, 60),
        ],
      );
      expect(stitchSleep(data.spans), hasLength(2));
      final report = data.report(today);
      expect(report.night!.asleep, minutes(270));
      expect(report.night!.timeInBed, minutes(270));
      expect(scored(report.sleep).value, 85);
    });

    test('parts split across local midnight land on different dates', () {
      final first = ringSleepSpans(
        wake: today.addDays(-1),
        startMinute: 1290,
        endMinute: 1420,
        periods: const [(ringLight, 130)],
        zone: saoPaulo,
      );
      final second = ringSleepSpans(
        wake: today,
        startMinute: 70,
        endMinute: 420,
        periods: const [(ringLight, 255), (ringLight, 95)],
        zone: saoPaulo,
      );
      final byDate = mainNightByDate(stitchSleep([...first, ...second]));
      expect(byDate[today]!.asleep, minutes(350));
      expect(byDate[today.addDays(-1)]!.asleep, minutes(130));
    });
  });

  group('naps', () {
    List<SleepSpan> napAt({
      required LocalDate wake,
      required int startMinute,
      required List<RingPeriod> periods,
    }) {
      final total = periods.fold(0, (sum, p) => sum + p.$2);
      return ringSleepSpans(
        wake: wake,
        startMinute: startMinute,
        endMinute: startMinute + total,
        periods: periods,
        zone: saoPaulo,
      );
    }

    final data = referenceNight(wake: today, zone: saoPaulo);
    final baseline = data.report(today);

    test('an afternoon nap on the wake date does not count', () {
      final withNap = data.report(
        today,
        extraSpans: napAt(
          wake: today,
          startMinute: 14 * 60,
          periods: const [(ringLight, 50), (ringDeep, 20)],
        ),
      );
      expect(withNap.night!.asleep, baseline.night!.asleep);
      expect(withNap.night!.start, baseline.night!.start);
      expect(scored(withNap.sleep).value, scored(baseline.sleep).value);
      expect(withNap.restingHeartRate, baseline.restingHeartRate);
    });

    test('an evening nap does not become the night of its own date', () {
      final previous = referenceNight(wake: today.addDays(-1), zone: saoPaulo);
      final nap = napAt(
        wake: today.addDays(-1),
        startMinute: 19 * 60,
        periods: const [(ringLight, 45)],
      );
      final byDate = mainNightByDate(
        stitchSleep([...previous.spans, ...data.spans, ...nap]),
      );
      expect(byDate, hasLength(2));
      expect(byDate[today.addDays(-1)]!.asleep, minutes(396));
      expect(byDate[today]!.asleep, minutes(396));
    });

    test('a nap ending within 60 minutes of bedtime joins the night', () {
      final nap = napAt(
        wake: today.addDays(-1),
        startMinute: 21 * 60 + 30,
        periods: const [(ringLight, 60)],
      );
      final night = stitchSleep([...data.spans, ...nap]).single;
      expect(night.gaps.single.duration, minutes(37));
      expect(night.asleep, minutes(456));
    });

    test('a nap alone on its date under an hour is not scored', () {
      final nap = napAt(
        wake: today,
        startMinute: 14 * 60,
        periods: const [(ringLight, 40)],
      );
      final night = mainNightByDate(stitchSleep(nap))[today];
      expect(sleepScore(night), isA<InsufficientData<SleepFactor>>());
    });

    test('known limit: a lone nap of an hour or more is scored', () {
      final nap = napAt(
        wake: today,
        startMinute: 14 * 60,
        periods: const [(ringLight, 70), (ringDeep, 30)],
      );
      final night = mainNightByDate(stitchSleep(nap))[today];
      expect(scored(sleepScore(night)).value, 57);
    });

    test('known limit: a nap longer than a short night takes the date', () {
      final short = referenceNight(
        wake: today,
        zone: saoPaulo,
        startMinute: 1410,
        endMinute: 90,
        periods: const [(ringLight, 120)],
      );
      final nap = napAt(
        wake: today,
        startMinute: 14 * 60,
        periods: const [(ringLight, 150)],
      );
      final report = short.report(today, extraSpans: nap);
      expect(report.night!.asleep, minutes(150));
      expect(report.night!.start, nap.first.start);
    });
  });

  group('short night', () {
    SyntheticNight short(int endMinute, List<RingPeriod> periods) =>
        referenceNight(
          wake: today,
          zone: saoPaulo,
          startMinute: 1410,
          endMinute: endMinute,
          periods: periods,
        );

    test('under an hour asleep is not scored and blocks readiness', () {
      final report = short(15, const [
        (ringLight, 30),
        (ringDeep, 15),
      ]).report(today);
      expect(report.night!.asleep, minutes(45));
      expect((report.sleep as InsufficientData<SleepFactor>).missing, [
        SleepFactor.duration,
      ]);
      expect(report.restingHeartRate, isNotNull);
      expect(report.hrv, isNull);
    });

    test('exactly an hour is scored', () {
      final report = short(30, const [(ringLight, 60)]).report(today);
      expect(scored(report.sleep).total, closeTo(34.375, eps));
      expect(scored(report.sleep).value, 34);
    });

    test('three and a half hours scores on duration, not on a floor', () {
      final report = short(195, const [
        (ringAwake, 5),
        (ringLight, 100),
        (ringDeep, 30),
        (ringLight, 80),
        (ringAwake, 10),
      ]).report(today);
      expect(report.night!.asleep, minutes(210));
      expect(scored(report.sleep).total, closeTo(64.3601, eps));
      expect(report.spo2, isNotNull);
    });

    test('too few hourly SpO2 readings give no summary', () {
      final report = short(30, const [(ringLight, 60)]).report(today);
      expect(report.spo2, isNull);
    });
  });

  group('missing heart rate', () {
    final full = referenceNight(wake: today, zone: saoPaulo).report(today);

    test(
      'a night of zero slots has no resting heart rate, keeps its score',
      () {
        final report = referenceNight(
          wake: today,
          zone: saoPaulo,
          heartRateOverride: (_) => 0,
        ).report(today);
        expect(report.restingHeartRate, isNull);
        expect(scored(report.sleep).value, scored(full.sleep).value);
      },
    );

    test('slots every 30 minutes can never meet 3 samples in a window', () {
      final report = referenceNight(
        wake: today,
        zone: saoPaulo,
        heartRateOverride: (at) => at.minute % 30 == 0 ? null : 0,
      ).report(today);
      expect(report.restingHeartRate, isNull);
    });

    test('a ring off the finger for the trough uses what is left', () {
      final off = saoPaulo.instantOf(today, 2 * 60);
      final back = saoPaulo.instantOf(today, 5 * 60);
      final report = referenceNight(
        wake: today,
        zone: saoPaulo,
        heartRateOverride: (at) =>
            !at.isBefore(off) && at.isBefore(back) ? 0 : null,
      ).report(today);
      expect(report.restingHeartRate, greaterThan(60));
      expect(report.restingHeartRate, lessThan(66));
    });

    test('scattered missed slots still give the trough when 3 remain', () {
      final troughStart = saoPaulo.instantOf(today, 3 * 60);
      final report = referenceNight(
        wake: today,
        zone: saoPaulo,
        heartRateOverride: (at) =>
            at == troughStart || at == troughStart.add(minutes(15)) ? 0 : null,
      ).report(today);
      expect(
        report.restingHeartRate,
        closeTo((52 + 51 + 52 + 52 + 63) / 5, eps),
      );
    });

    test('readiness says resting heart rate is what is missing', () {
      final result = readiness(
        sleepScore: 81,
        hrv: const BaselineDeviation(today: 50, baseline: 50, zScore: 0),
        restingHeartRate: null,
      );
      expect((result as InsufficientData<ReadinessFactor>).missing, [
        ReadinessFactor.restingHeartRate,
      ]);
    });
  });

  group('baseline runs', () {
    final tonight = referenceNight(
      wake: today,
      zone: saoPaulo,
      hrvBase: 44,
      heartRateShift: 4,
    ).report(today);

    ActivityLoad? load() => activityLoad([
      for (var age = 1; age <= 28; age++)
        if (age != 12 && age != 20)
          (
            date: today.addDays(-age),
            value:
                (age <= 7
                        ? const [420, 380, 510, 0, 460, 390, 440][age - 1]
                        : 300 + (age % 5) * 20)
                    .toDouble(),
          ),
    ], today: today);

    test('7 nights before today make both baselines ready', () {
      final nights = history(today);
      final hrv = hrvBaseline(
        nightly(nights, (r) => r.hrv),
        today: today,
      ) as BaselineReady;
      final resting = restingHeartRateBaseline(
        nightly(nights, (r) => r.restingHeartRate),
        today: today,
      ) as BaselineReady;

      expect(hrv.days, 7);
      expect(hrv.typical, closeTo(50.5018, eps));
      expect(hrv.sdOnScale, closeTo(0.0566, eps));
      expect(resting.days, 7);
      expect(resting.typical, closeTo(51.9524, eps));
      expect(resting.sdOnScale, closeTo(1.1127, eps));

      final hrvToday = hrv.compare(tonight.hrv!);
      final restingToday = resting.compare(tonight.restingHeartRate!);
      expect(hrvToday.zScore, closeTo(-2.4349, eps));
      expect(restingToday.zScore, closeTo(3.3381, eps));

      final result = scored(
        readiness(
          sleepScore: scored(tonight.sleep).value,
          hrv: hrvToday,
          restingHeartRate: restingToday,
          activityLoad: load(),
        ),
      );
      expect(result.of(ReadinessFactor.hrv)!.subscore, closeTo(0.1413, eps));
      expect(result.of(ReadinessFactor.restingHeartRate)!.subscore, 0);
      expect(result.of(ReadinessFactor.activityLoad)!.subscore, 1);
      expect(result.total, closeTo(47.5884, eps));
      expect(result.value, 48);
    });

    test('readiness without activity load rescales the other three', () {
      final nights = history(today);
      final hrv = hrvBaseline(
        nightly(nights, (r) => r.hrv),
        today: today,
      ) as BaselineReady;
      final resting = restingHeartRateBaseline(
        nightly(nights, (r) => r.restingHeartRate),
        today: today,
      ) as BaselineReady;
      final result = scored(
        readiness(
          sleepScore: scored(tonight.sleep).value,
          hrv: hrv.compare(tonight.hrv!),
          restingHeartRate: resting.compare(tonight.restingHeartRate!),
        ),
      );
      expect(result.total, closeTo(38.3393, eps));
      expect(result.value, 38);
    });

    test('activity load from worn days only', () {
      final value = load()!;
      expect(value.acuteDays, 7);
      expect(value.chronicDays, 26);
      expect(value.acute, closeTo(371.4286, eps));
      expect(value.chronic, closeTo(350.7692, eps));
      expect(value.ratio, closeTo(1.0589, eps));
    });

    test('6 nights keep building and readiness names what is missing', () {
      final nights = history(today, nights: 6);
      final hrv = hrvBaseline(nightly(nights, (r) => r.hrv), today: today);
      final resting = restingHeartRateBaseline(
        nightly(nights, (r) => r.restingHeartRate),
        today: today,
      );
      expect((hrv as BaselineBuilding).daysCollected, 6);
      expect(hrv.daysNeeded, 7);
      expect((resting as BaselineBuilding).daysCollected, 6);
      final result = readiness(
        sleepScore: scored(tonight.sleep).value,
        hrv: null,
        restingHeartRate: null,
      );
      expect((result as InsufficientData<ReadinessFactor>).missing, [
        ReadinessFactor.hrv,
        ReadinessFactor.restingHeartRate,
      ]);
    });

    test('today does not count toward its own baseline', () {
      final values = [
        ...nightly(history(today, nights: 6), (r) => r.hrv),
        (date: today, value: tonight.hrv!),
      ];
      expect(hrvBaseline(values, today: today), isA<BaselineBuilding>());
    });

    test('a night older than 28 days does not count', () {
      final values = [
        (date: today.addDays(-29), value: 50.0),
        ...nightly(history(today, nights: 6), (r) => r.hrv),
      ];
      final result = hrvBaseline(values, today: today) as BaselineBuilding;
      expect(result.daysCollected, 6);
    });

    test('a night without heart rate is a missing date, not a zero', () {
      final nights = history(today);
      nights[3] = referenceNight(
        wake: today.addDays(-4),
        zone: saoPaulo,
        heartRateOverride: (_) => 0,
      );
      final values = nightly(nights, (r) => r.restingHeartRate);
      expect(values, hasLength(6));
      final result = restingHeartRateBaseline(values, today: today);
      expect((result as BaselineBuilding).daysCollected, 6);
    });

    test('a run of nights without code 4 marks REM as not reported', () {
      List<SleepNight> nights(int count, List<RingPeriod> periods) => [
        for (var age = 1; age <= count; age++)
          stitchSleep(
            referenceNight(
              wake: today.addDays(-age),
              zone: saoPaulo,
              periods: periods,
            ).spans,
          ).single,
      ];
      final noRem = withoutRem(referencePeriods);
      expect(RemReporting.ofNights(nights(6, noRem)), RemReporting.unknown);
      expect(RemReporting.ofNights(nights(7, noRem)), RemReporting.absent);
      expect(
        RemReporting.ofNights(nights(7, referencePeriods)),
        RemReporting.reported,
      );
    });
  });
}
