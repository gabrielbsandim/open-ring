import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/trends/domain/trend_series.dart';

const _today = LocalDate(2026, 11, 10);

DailyValue _at(int age, double value) =>
    (date: _today.addDays(-age), value: value);

void main() {
  test('lays out one slot per date, oldest first, ending today', () {
    final series = TrendSeries.of(const [], today: _today, days: 7);

    expect(series.days, 7);
    expect(series.firstDate, const LocalDate(2026, 11, 4));
    expect(series.points.last.date, _today);
    expect(series.hasStats, isFalse);
    expect(series.change, isNull);
  });

  test('keeps gaps as gaps and leaves them out of the statistics', () {
    final series = TrendSeries.of(
      [_at(6, 60), _at(4, 56), _at(1, 58)],
      today: _today,
      days: 7,
    );

    expect(
      [for (final p in series.points) p.value],
      [60, null, 56, null, null, 58, null],
    );
    expect(series.mean, 58);
    expect(series.min, 56);
    expect(series.max, 60);
    expect(series.measuredDays, 3);
    expect(series.latest, isNull);
  });

  test('a single sample is its own mean, min and max with no trend', () {
    final series = TrendSeries.of([_at(0, 46)], today: _today, days: 30);

    expect(series.mean, 46);
    expect(series.min, 46);
    expect(series.max, 46);
    expect(series.measuredDays, 1);
    expect(series.latest, 46);
    expect(series.change, isNull);
  });

  test('averages repeated values of one date', () {
    final series = TrendSeries.of(
      [_at(2, 50), _at(2, 54)],
      today: _today,
      days: 7,
    );

    expect(series.points[4].value, 52);
    expect(series.measuredDays, 1);
  });

  test('drops values outside the range and non finite values', () {
    final series = TrendSeries.of(
      [_at(7, 99), _at(-1, 99), _at(3, double.nan), _at(3, 61)],
      today: _today,
      days: 7,
    );

    expect(series.measuredDays, 1);
    expect(series.mean, 61);
  });

  test('a partial last day is drawn but stays out of the statistics', () {
    final series = TrendSeries.of(
      [_at(2, 8000), _at(1, 6000), _at(0, 1200)],
      today: _today,
      days: 7,
      partialLast: true,
    );

    expect(series.latest, 1200);
    expect(series.min, 6000);
    expect(series.mean, 7000);
    expect(series.measuredDays, 2);
  });

  test('compares the second half of the range with the first', () {
    final series = TrendSeries.of(
      [_at(6, 60), _at(5, 62), _at(4, 61), _at(2, 56), _at(1, 55)],
      today: _today,
      days: 7,
    );

    expect(series.change, closeTo(55.5 - 61, 1e-9));
  });

  test('needs two values in each half before naming a direction', () {
    final series = TrendSeries.of(
      [_at(6, 60), _at(2, 56), _at(1, 55)],
      today: _today,
      days: 7,
    );

    expect(series.change, isNull);
  });

  test('a DST change neither adds nor drops a date', () {
    const today = LocalDate(2026, 3, 31);
    final series = TrendSeries.of(
      const [
        (date: LocalDate(2026, 3, 28), value: 1),
        (date: LocalDate(2026, 3, 29), value: 2),
        (date: LocalDate(2026, 3, 30), value: 3),
      ],
      today: today,
      days: 7,
    );

    expect(
      [for (final p in series.points) p.date.iso],
      [
        '2026-03-25',
        '2026-03-26',
        '2026-03-27',
        '2026-03-28',
        '2026-03-29',
        '2026-03-30',
        '2026-03-31',
      ],
    );
    expect(series.points[4].value, 2);
  });

  test('counts settled values inside a band, edges included', () {
    final series = TrendSeries.of(
      [_at(3, 55), _at(2, 58), _at(1, 62), _at(0, 63)],
      today: _today,
      days: 7,
    );

    expect(series.inside((low: 58, high: 62)), 2);
  });

  test('rejects a range without days', () {
    expect(
      () => TrendSeries.of(const [], today: _today, days: 0),
      throwsArgumentError,
    );
  });
}
