import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/trajectory/domain/monday_projection.dart';

const _monday = LocalDate(2026, 11, 23);
const _wednesday = LocalDate(2026, 11, 25);
final _createdAt = DateTime.utc(2026, 11, 25, 9);

List<DailyValue> _series({
  required LocalDate from,
  required LocalDate to,
  double start = 80,
  double perDay = -0.05,
  double wobble = 0.3,
}) => [
  for (var i = 0; from.addDays(i).compareTo(to) <= 0; i++)
    (
      date: from.addDays(i),
      value: start + perDay * i + (i.isEven ? wobble : -wobble),
    ),
];

List<DailyValue> _daysBack(List<int> backs) => [
  for (final back in backs)
    (date: _monday.addDays(-back), value: 80.0 + (back % 4 == 0 ? 0.3 : -0.3)),
];

void main() {
  group('mondayProjection', () {
    test('keys the band by the Monday of the week and keeps createdAt', () {
      final daily = _series(from: const LocalDate(2026, 10, 20), to: _monday);

      final projection = mondayProjection(
        today: _wednesday,
        daily: daily,
        createdAt: _createdAt,
      );

      expect(projection, isNotNull);
      expect(projection!.monday, _monday);
      expect(projection.createdAt, _createdAt);
    });

    test('stores the firm band as it stood on the Monday', () {
      final daily = _series(
        from: const LocalDate(2026, 10, 20),
        to: _wednesday,
      );
      final past = [
        for (final day in daily)
          if (day.date.compareTo(_monday) <= 0) day,
      ];
      final trend = weightTrend(past).last.value;
      final rate = weightRate(past, today: _monday) as WeightRateReady;
      final band = weightScenario(
        trend,
        rate,
        weightNoise(past),
        trajectoryFirmDays,
      );

      final projection = mondayProjection(
        today: _wednesday,
        daily: daily,
        createdAt: _createdAt,
      )!;

      expect(projection.trendKg, closeTo(trend, 1e-9));
      expect(projection.rateKgPerWeek, closeTo(rate.perWeek, 1e-9));
      expect(projection.lowKg, closeTo(band.low, 1e-9));
      expect(projection.midKg, closeTo(band.mid, 1e-9));
      expect(projection.highKg, closeTo(band.high, 1e-9));
      expect(projection.lowKg, lessThanOrEqualTo(projection.midKg));
      expect(projection.midKg, lessThanOrEqualTo(projection.highKg));
    });

    test('ignores weigh-ins after the Monday', () {
      final until = _series(from: const LocalDate(2026, 10, 20), to: _monday);
      final after = [
        ...until,
        for (var i = 1; i <= 3; i++)
          (date: _monday.addDays(i), value: 95.0 + i),
      ];

      final plain = mondayProjection(
        today: const LocalDate(2026, 11, 26),
        daily: until,
        createdAt: _createdAt,
      )!;
      final later = mondayProjection(
        today: const LocalDate(2026, 11, 26),
        daily: after,
        createdAt: _createdAt,
      )!;

      expect(later.trendKg, plain.trendKg);
      expect(later.lowKg, plain.lowKg);
      expect(later.midKg, plain.midKg);
      expect(later.highKg, plain.highKg);
    });

    test('on the Monday itself the snapshot is that day', () {
      final daily = _series(from: const LocalDate(2026, 10, 20), to: _monday);

      final projection = mondayProjection(
        today: _monday,
        daily: daily,
        createdAt: _createdAt,
      );

      expect(projection!.monday, _monday);
    });

    test('is null with no weigh-ins', () {
      expect(
        mondayProjection(
          today: _wednesday,
          daily: const <DailyValue>[],
          createdAt: _createdAt,
        ),
        isNull,
      );
    });

    test('is null when the Monday snapshot is still building', () {
      final daily = _series(
        from: const LocalDate(2026, 11, 11),
        to: _wednesday,
      );

      expect(
        mondayProjection(
          today: _wednesday,
          daily: daily,
          createdAt: _createdAt,
        ),
        isNull,
      );
    });

    test('8 days spanning 14 on the Monday is ready', () {
      final ready = _daysBack([14, 12, 10, 8, 6, 4, 2, 0]);

      expect(
        mondayProjection(today: _monday, daily: ready, createdAt: _createdAt),
        isNotNull,
      );
    });

    test('one day fewer than 8 is building', () {
      final seven = _daysBack([14, 12, 10, 8, 6, 4, 2]);

      expect(
        mondayProjection(today: _monday, daily: seven, createdAt: _createdAt),
        isNull,
      );
    });

    test('is null when the loss on the Monday is guarded', () {
      final steep = _series(
        from: const LocalDate(2026, 10, 20),
        to: _monday,
        start: 100,
        perDay: -1,
        wobble: 0.1,
      );

      expect(
        mondayProjection(
          today: _wednesday,
          daily: steep,
          createdAt: _createdAt,
        ),
        isNull,
      );
    });

    test('is null when the last weigh-in is a whole window old', () {
      final old = _series(
        from: const LocalDate(2026, 9, 1),
        to: const LocalDate(2026, 9, 30),
      );

      expect(
        mondayProjection(today: _wednesday, daily: old, createdAt: _createdAt),
        isNull,
      );
    });
  });
}
