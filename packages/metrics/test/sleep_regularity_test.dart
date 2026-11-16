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

List<SleepSpan> nightly(
  int count, {
  int hour = 23,
  Duration length = const Duration(hours: 8),
}) => [
  for (var i = -1; i < count; i++) span(first.addDays(i), hour, 0, length),
];

void main() {
  test('identical days give 100', () {
    final result = sleepRegularity(nightly(15), days: run(15))!;

    expect(result.index, 100);
    expect(result.pairs, 14);
  });

  test('days with no sleep at all are identical too', () {
    expect(sleepRegularity(const [], days: run(15))!.index, 100);
  });

  test('opposite days give -100', () {
    final spans = [
      for (var i = 0; i < 15; i++)
        span(first.addDays(i), i.isEven ? 0 : 12, 0, const Duration(hours: 12)),
    ];

    expect(sleepRegularity(spans, days: run(15))!.index, -100);
  });

  test('one night an hour late costs the epochs that differ', () {
    final spans = [
      for (var i = -1; i < 15; i++)
        span(
          first.addDays(i == 6 ? 7 : i),
          i == 6 ? 0 : 23,
          0,
          const Duration(hours: 8),
        ),
    ];
    final result = sleepRegularity(spans, days: run(15))!;

    expect(
      result.index,
      closeTo(-100 + 200 * (14 * 288 - 48) / (14 * 288), 1e-9),
    );
  });

  test('a pair with a day that is not valid is skipped', () {
    final days = run(17)..remove(first.addDays(8));
    final result = sleepRegularity(nightly(17), days: days)!;

    expect(result.pairs, 14);
    expect(result.index, 100);
  });

  test('fewer than 14 pairs give no index', () {
    expect(sleepRegularity(nightly(14), days: run(14)), isNull);
    expect(sleepRegularity(nightly(15), days: const {}), isNull);
  });

  test('a nap counts as sleep', () {
    final spans = [
      ...nightly(15),
      span(first.addDays(3), 14, 0, const Duration(minutes: 30)),
    ];
    final result = sleepRegularity(spans, days: run(15))!;

    expect(
      result.index,
      closeTo(-100 + 200 * (14 * 288 - 12) / (14 * 288), 1e-9),
    );
  });

  test('time awake inside the night is not sleep', () {
    final spans = [
      ...nightly(15),
      span(
        first.addDays(3),
        14,
        0,
        const Duration(minutes: 30),
        phase: SleepPhase.awake,
      ),
    ];

    expect(sleepRegularity(spans, days: run(15))!.index, 100);
  });

  test('days are read on the wall clock of each span', () {
    const offset = Duration(hours: -3);
    final spans = [
      for (var i = -1; i < 15; i++)
        span(
          first.addDays(i),
          23,
          0,
          const Duration(hours: 8),
          utcOffset: offset,
        ),
    ];

    expect(sleepRegularity(spans, days: run(15))!.index, 100);
  });

  test('a span that starts off the grid marks only the epochs it covers', () {
    final spans = [
      ...nightly(15),
      span(first.addDays(3), 14, 2, const Duration(minutes: 10)),
    ];
    final result = sleepRegularity(spans, days: run(15))!;

    expect(
      result.index,
      closeTo(-100 + 200 * (14 * 288 - 4) / (14 * 288), 1e-9),
    );
  });
}
