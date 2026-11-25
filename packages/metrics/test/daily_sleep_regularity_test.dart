import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const first = LocalDate(2026, 10, 1);

SleepSpan span(
  LocalDate date,
  int hour,
  int minute,
  Duration length, {
  SleepPhase phase = SleepPhase.light,
  Duration utcOffset = Duration.zero,
}) {
  final start = DateTime.utc(
    date.year,
    date.month,
    date.day,
    hour,
    minute,
  ).subtract(utcOffset);
  return SleepSpan(
    start: start,
    end: start.add(length),
    phase: phase,
    utcOffset: utcOffset,
  );
}

Set<LocalDate> run(int count) => {
  for (var i = 0; i < count; i++) first.addDays(i),
};

List<SleepSpan> nightly(int count) => [
  for (var i = -1; i < count; i++)
    span(first.addDays(i), 23, 0, const Duration(hours: 8)),
];

Map<LocalDate, double> byDate(List<DailyValue> values) => {
  for (final value in values) value.date: value.value,
};

double scored(int same) => -100 + 200 * same / 288;

void main() {
  test(
    '3. identical days give one 100 for each pair, dated by the second day',
    () {
      final values = byDate(dailySleepRegularity(nightly(4), days: run(4)));

      expect(values, {
        first.addDays(1): 100,
        first.addDays(2): 100,
        first.addDays(3): 100,
      });
    },
  );

  test('3. a half hour nap on one day costs both pairs it belongs to', () {
    final spans = [
      ...nightly(6),
      span(first.addDays(3), 14, 0, const Duration(minutes: 30)),
    ];
    final values = byDate(dailySleepRegularity(spans, days: run(6)));

    expect(values.length, 5);
    expect(values[first.addDays(1)], 100);
    expect(values[first.addDays(2)], 100);
    expect(values[first.addDays(3)], closeTo(scored(288 - 6), 1e-9));
    expect(values[first.addDays(4)], closeTo(scored(288 - 6), 1e-9));
    expect(values[first.addDays(5)], 100);
  });

  test('3. opposite days give -100', () {
    final spans = [
      for (var i = 0; i < 4; i++)
        span(first.addDays(i), i.isEven ? 0 : 12, 0, const Duration(hours: 12)),
    ];
    final values = byDate(dailySleepRegularity(spans, days: run(4)));

    expect(values.values, everyElement(-100));
    expect(values.length, 3);
  });

  test('3. the mean over the days equals the sleepRegularity index', () {
    final spans = [
      for (var i = -1; i < 15; i++)
        span(
          first.addDays(i == 6 ? 7 : i),
          i == 6 ? 0 : 23,
          0,
          const Duration(hours: 8),
        ),
      span(first.addDays(3), 14, 0, const Duration(minutes: 30)),
    ];
    final days = run(15);
    final values = dailySleepRegularity(spans, days: days);
    final mean =
        values.fold<double>(0, (sum, v) => sum + v.value) / values.length;

    expect(values.length, sleepRegularity(spans, days: days)!.pairs);
    expect(mean, closeTo(sleepRegularity(spans, days: days)!.index, 1e-9));
  });

  test('3. a day with no sleep that is in days still gives a value', () {
    final values = byDate(dailySleepRegularity(const [], days: run(3)));

    expect(values, {first.addDays(1): 100, first.addDays(2): 100});
  });

  test('3. time awake is not sleep', () {
    final spans = [
      ...nightly(4),
      span(
        first.addDays(2),
        14,
        0,
        const Duration(minutes: 30),
        phase: SleepPhase.awake,
      ),
    ];

    expect(
      byDate(dailySleepRegularity(spans, days: run(4))).values,
      everyElement(100),
    );
  });

  test('3. days are read on the wall clock of each span', () {
    const offset = Duration(hours: -3);
    final spans = [
      for (var i = -1; i < 4; i++)
        span(
          first.addDays(i),
          23,
          0,
          const Duration(hours: 8),
          utcOffset: offset,
        ),
    ];

    expect(
      byDate(dailySleepRegularity(spans, days: run(4))).values,
      everyElement(100),
    );
  });

  test('4. a day missing from days breaks both pairs it belongs to', () {
    final days = run(7)..remove(first.addDays(3));
    final values = byDate(dailySleepRegularity(nightly(7), days: days));

    expect(values.keys.toSet(), {
      first.addDays(1),
      first.addDays(2),
      first.addDays(5),
      first.addDays(6),
    });
  });

  test('4. a missing day with a night of sleep gives no value, not 100', () {
    final days = {first, first.addDays(2)};
    final values = dailySleepRegularity(nightly(3), days: days);

    expect(values, isEmpty);
  });

  test('4. empty days and a single day give no values', () {
    expect(dailySleepRegularity(nightly(3), days: const {}), isEmpty);
    expect(dailySleepRegularity(nightly(3), days: {first}), isEmpty);
  });

  test('4. days that are not consecutive give no values', () {
    final days = {first, first.addDays(2), first.addDays(4)};

    expect(dailySleepRegularity(nightly(5), days: days), isEmpty);
  });
}
