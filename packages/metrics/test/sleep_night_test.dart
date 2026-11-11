import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const saoPaulo = Duration(hours: -3);

List<SleepSpan> run(
  DateTime from,
  List<(SleepPhase, int)> parts, {
  Duration offset = saoPaulo,
}) {
  var at = from;
  return [
    for (final (phase, minutes) in parts)
      SleepSpan(
        start: at,
        end: at = at.add(Duration(minutes: minutes)),
        phase: phase,
        utcOffset: offset,
      ),
  ];
}

const SleepPhase light = SleepPhase.light;
const SleepPhase deep = SleepPhase.deep;
const SleepPhase rem = SleepPhase.rem;
const SleepPhase awake = SleepPhase.awake;

final typicalStart = DateTime.utc(2026, 11, 10, 2);

List<SleepSpan> typicalNight() => run(typicalStart, [
  (awake, 15),
  (light, 60),
  (deep, 50),
  (light, 40),
  (rem, 30),
  (awake, 5),
  (light, 60),
  (deep, 30),
  (rem, 40),
  (light, 60),
  (rem, 30),
  (awake, 10),
]);

void main() {
  group('typical night', () {
    final night = stitchSleep(typicalNight()).single;

    test('measures bed, sleep, latency and efficiency', () {
      expect(night.start, typicalStart);
      expect(night.timeInBed, const Duration(minutes: 430));
      expect(night.asleep, const Duration(minutes: 400));
      expect(night.awake, const Duration(minutes: 30));
      expect(night.latency, const Duration(minutes: 15));
      expect(night.efficiency, closeTo(400 / 430, 1e-12));
      expect(night.gaps, isEmpty);
    });

    test('splits stage time as a share of time asleep', () {
      expect(night.timeIn(deep), const Duration(minutes: 80));
      expect(night.timeIn(light), const Duration(minutes: 220));
      expect(night.timeIn(rem), const Duration(minutes: 100));
      expect(night.share(deep), closeTo(0.2, 1e-12));
      expect(night.share(rem), closeTo(0.25, 1e-12));
      expect(night.share(light), closeTo(0.55, 1e-12));
      expect(night.share(awake), closeTo(30 / 430, 1e-12));
    });

    test(
      'counts mid night wakes, not the wait to fall asleep or the final wake',
      () {
        expect(night.awakenings, hasLength(1));
        final wake = night.awakenings.single;
        expect(wake.start, typicalStart.add(const Duration(minutes: 195)));
        expect(wake.duration, const Duration(minutes: 5));
        expect(wake.bridgesGap, isFalse);
        expect(night.wakeAfterSleepOnset, const Duration(minutes: 5));
      },
    );

    test('belongs to the local date it ends on', () {
      expect(night.end, DateTime.utc(2026, 11, 10, 9, 10));
      expect(night.date, const LocalDate(2026, 11, 10));
    });

    test('ignores input order', () {
      final shuffled = typicalNight().reversed.toList();
      final again = stitchSleep(shuffled).single;
      expect(again.asleep, night.asleep);
      expect(again.awakenings.length, night.awakenings.length);
    });
  });

  group('split night', () {
    final first = run(DateTime.utc(2026, 11, 10, 2, 30), [
      (light, 120),
      (deep, 60),
      (light, 102),
    ]);
    final wokeAt = DateTime.utc(2026, 11, 10, 7, 12);

    test('joins two stretches and reports the gap as a wake', () {
      final second = run(wokeAt.add(const Duration(minutes: 9)), [
        (light, 60),
        (rem, 39),
      ]);
      final nights = stitchSleep([...first, ...second]);
      expect(nights, hasLength(1));
      final night = nights.single;
      expect(night.gaps.single.start, wokeAt);
      expect(night.gaps.single.duration, const Duration(minutes: 9));
      final wake = night.awakenings.single;
      expect(
        LocalDate.fromInstant(wake.start, saoPaulo),
        const LocalDate(2026, 11, 10),
      );
      expect(wake.start.add(saoPaulo), DateTime.utc(2026, 11, 10, 4, 12));
      expect(wake.duration, const Duration(minutes: 9));
      expect(wake.bridgesGap, isTrue);
      expect(night.asleep, const Duration(minutes: 381));
      expect(night.timeInBed, const Duration(minutes: 390));
    });

    test('merges the gap with awake time around it into one wake', () {
      final second = run(wokeAt.add(const Duration(minutes: 9)), [
        (awake, 3),
        (light, 60),
      ]);
      final night = stitchSleep([...first, ...second]).single;
      expect(night.awakenings.single.duration, const Duration(minutes: 12));
      expect(night.wakeAfterSleepOnset, const Duration(minutes: 12));
    });

    test('a gap of exactly maxGap joins, one minute more splits', () {
      final joined = run(wokeAt.add(defaultMaxStitchGap), [(light, 60)]);
      expect(stitchSleep([...first, ...joined]), hasLength(1));

      final apart = run(
        wokeAt.add(defaultMaxStitchGap + const Duration(minutes: 1)),
        [(light, 60)],
      );
      final nights = stitchSleep([...first, ...apart]);
      expect(nights, hasLength(2));
      expect(nights.first.asleep, const Duration(minutes: 282));
      expect(nights.last.asleep, const Duration(minutes: 60));
    });

    test('maxGap of zero still joins touching spans', () {
      final touching = run(wokeAt, [(light, 30)]);
      final gapped = run(wokeAt.add(const Duration(minutes: 31)), [
        (light, 30),
      ]);
      final nights = stitchSleep([
        ...first,
        ...touching,
        ...gapped,
      ], maxGap: Duration.zero);
      expect(nights, hasLength(2));
      expect(nights.first.asleep, const Duration(minutes: 312));
    });
  });

  group('edge cases', () {
    test('no spans means no nights', () {
      expect(stitchSleep(const []), isEmpty);
    });

    test('a single span is a night with no latency and no wakes', () {
      final night = stitchSleep(run(typicalStart, [(light, 30)])).single;
      expect(night.asleep, const Duration(minutes: 30));
      expect(night.latency, Duration.zero);
      expect(night.efficiency, 1);
      expect(night.awakenings, isEmpty);
      expect(night.share(deep), 0);
    });

    test('drops empty spans and nights with no sleep at all', () {
      final empty = SleepSpan(
        start: typicalStart,
        end: typicalStart,
        phase: light,
        utcOffset: saoPaulo,
      );
      expect(stitchSleep([empty]), isEmpty);
      expect(stitchSleep(run(typicalStart, [(awake, 45)])), isEmpty);
    });

    test(
      'an awake only night has no onset, no latency and no stage shares',
      () {
        final night = SleepNight(run(typicalStart, [(awake, 45)]));
        expect(night.sleepOnset, isNull);
        expect(night.latency, isNull);
        expect(night.share(deep), isNull);
        expect(night.share(awake), 1);
        expect(night.awakenings, isEmpty);
      },
    );

    test('overlapping spans are clipped so time is counted once', () {
      final base = run(typicalStart, [(light, 60), (deep, 60)]);
      final overlapping = SleepSpan(
        start: typicalStart.add(const Duration(minutes: 90)),
        end: typicalStart.add(const Duration(minutes: 150)),
        phase: rem,
        utcOffset: saoPaulo,
      );
      final inside = SleepSpan(
        start: typicalStart.add(const Duration(minutes: 10)),
        end: typicalStart.add(const Duration(minutes: 20)),
        phase: awake,
        utcOffset: saoPaulo,
      );
      final night = stitchSleep([...base, overlapping, inside]).single;
      expect(night.timeInBed, const Duration(minutes: 150));
      expect(night.asleep, const Duration(minutes: 150));
      expect(night.timeIn(rem), const Duration(minutes: 30));
      expect(night.awakenings, isEmpty);
    });

    test('spans with the same start resolve the same in any input order', () {
      SleepSpan span(SleepPhase phase, int minutes) => SleepSpan(
        start: typicalStart,
        end: typicalStart.add(Duration(minutes: minutes)),
        phase: phase,
        utcOffset: saoPaulo,
      );
      final short = span(light, 30);
      final long = span(deep, 45);
      final tieA = span(rem, 45);
      final one = stitchSleep([short, long, tieA]).single;
      final two = stitchSleep([tieA, long, short]).single;
      for (final phase in [light, deep, rem]) {
        expect(two.timeIn(phase), one.timeIn(phase));
      }
      expect(one.timeIn(deep), const Duration(minutes: 45));
      expect(one.timeIn(light), Duration.zero);
    });

    test('rejects a negative maxGap and an empty night', () {
      expect(
        () => stitchSleep(const [], maxGap: const Duration(minutes: -1)),
        throwsArgumentError,
      );
      expect(() => SleepNight(const []), throwsArgumentError);
    });
  });

  group('night date', () {
    test('Kiritimati: the local wake date is a day ahead of UTC', () {
      const kiritimati = Duration(hours: 14);
      final night = stitchSleep(
        run(DateTime.utc(2026, 11, 9, 8), [(light, 480)], offset: kiritimati),
      ).single;
      expect(night.end, DateTime.utc(2026, 11, 9, 16));
      expect(night.date, const LocalDate(2026, 11, 10));
    });

    test('Honolulu day sleep: the local wake date is a day behind UTC', () {
      const honolulu = Duration(hours: -10);
      final night = stitchSleep(
        run(DateTime.utc(2026, 11, 10, 18), [(light, 420)], offset: honolulu),
      ).single;
      expect(night.end, DateTime.utc(2026, 11, 11, 1));
      expect(night.date, const LocalDate(2026, 11, 10));
    });

    test('a wake at local midnight starts the new date', () {
      final atMidnight = stitchSleep(
        run(DateTime.utc(2026, 11, 10, 21), [(light, 360)]),
      ).single;
      expect(atMidnight.date, const LocalDate(2026, 11, 11));
      final justBefore = stitchSleep(
        run(DateTime.utc(2026, 11, 10, 21), [(light, 359)]),
      ).single;
      expect(justBefore.date, const LocalDate(2026, 11, 10));
    });

    test(
      'Berlin fall back: real elapsed time, date from the offset at wake',
      () {
        const cest = Duration(hours: 2);
        const cet = Duration(hours: 1);
        final spans = [
          ...run(DateTime.utc(2026, 10, 24, 20, 30), [
            (light, 210),
            (deep, 60),
          ], offset: cest),
          ...run(DateTime.utc(2026, 10, 25, 1), [(light, 300)], offset: cet),
        ];
        final night = stitchSleep(spans).single;
        expect(night.timeInBed, const Duration(hours: 9, minutes: 30));
        expect(night.asleep, const Duration(hours: 9, minutes: 30));
        expect(night.end.add(cet), DateTime.utc(2026, 10, 25, 7));
        expect(night.date, const LocalDate(2026, 10, 25));
        expect(night.gaps, isEmpty);
      },
    );

    test('New York spring forward: the lost hour is not counted', () {
      const est = Duration(hours: -5);
      const edt = Duration(hours: -4);
      final spans = [
        ...run(DateTime.utc(2026, 3, 8, 4), [(light, 180)], offset: est),
        ...run(DateTime.utc(2026, 3, 8, 7), [
          (deep, 60),
          (light, 180),
        ], offset: edt),
      ];
      final night = stitchSleep(spans).single;
      expect(night.timeInBed, const Duration(hours: 7));
      expect(night.date, const LocalDate(2026, 3, 8));
    });

    test('host local DateTime values give the same night as UTC ones', () {
      final utc = stitchSleep(typicalNight()).single;
      final local = stitchSleep([
        for (final s in typicalNight())
          SleepSpan(
            start: s.start.toLocal(),
            end: s.end.toLocal(),
            phase: s.phase,
            utcOffset: s.utcOffset,
          ),
      ]).single;
      expect(local.date, utc.date);
      expect(local.timeInBed, utc.timeInBed);
      expect(local.asleep, utc.asleep);
      expect(local.latency, utc.latency);
    });
  });

  group('mainNightByDate', () {
    test('keeps the night with the most sleep for each date', () {
      final night = stitchSleep(typicalNight()).single;
      final nap = stitchSleep(
        run(DateTime.utc(2026, 11, 10, 17), [(light, 40)]),
      ).single;
      final nextNight = stitchSleep(
        run(DateTime.utc(2026, 11, 11, 2), [(light, 420)]),
      ).single;
      final byDate = mainNightByDate([nap, night, nextNight]);
      expect(
        byDate.keys,
        unorderedEquals([
          const LocalDate(2026, 11, 10),
          const LocalDate(2026, 11, 11),
        ]),
      );
      expect(byDate[const LocalDate(2026, 11, 10)], same(night));
      expect(byDate[const LocalDate(2026, 11, 11)], same(nextNight));
      expect(mainNightByDate(const []), isEmpty);
    });
  });
}
