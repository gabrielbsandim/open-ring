import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

void main() {
  test('reads the wall clock date at the given offset, not the host zone', () {
    final instant = DateTime.utc(2026, 11, 9, 20);
    expect(
      LocalDate.fromInstant(instant, const Duration(hours: 14)),
      const LocalDate(2026, 11, 10),
    );
    expect(
      LocalDate.fromInstant(instant, const Duration(hours: -3)),
      const LocalDate(2026, 11, 9),
    );
    expect(
      LocalDate.fromInstant(instant.toLocal(), const Duration(hours: 14)),
      const LocalDate(2026, 11, 10),
    );
  });

  test('adds days across month, year and leap day boundaries', () {
    expect(
      const LocalDate(2026, 12, 31).addDays(1),
      const LocalDate(2027, 1, 1),
    );
    expect(
      const LocalDate(2028, 3, 1).addDays(-1),
      const LocalDate(2028, 2, 29),
    );
    expect(
      const LocalDate(2026, 11, 10).addDays(-28),
      const LocalDate(2026, 10, 13),
    );
  });

  test('counts whole days even across a DST change', () {
    expect(
      const LocalDate(2026, 10, 26).daysSince(const LocalDate(2026, 10, 24)),
      2,
    );
    expect(
      const LocalDate(2026, 3, 1).daysSince(const LocalDate(2026, 3, 9)),
      -8,
    );
  });

  test('orders and prints as ISO 8601', () {
    final dates = [
      const LocalDate(2026, 11, 10),
      const LocalDate(2026, 1, 2),
      const LocalDate(2025, 12, 31),
    ]..sort((a, b) => a.compareTo(b));
    expect(dates.map((d) => d.iso), ['2025-12-31', '2026-01-02', '2026-11-10']);
  });
}
