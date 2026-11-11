import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const today = LocalDate(2026, 11, 10);

List<DailyValue> days(Iterable<int> ago, double kcal) => [
  for (final a in ago) (date: today.addDays(-a), value: kcal),
];

Iterable<int> range(int from, int to) => [for (var i = from; i <= to; i++) i];

void main() {
  test('acute week over the 28 day mean that includes it', () {
    final load = activityLoad([
      ...days(range(1, 7), 600),
      ...days(range(8, 28), 400),
    ], today: today)!;
    expect(load.acute, 600);
    expect(load.chronic, 450);
    expect(load.ratio, closeTo(4 / 3, 1e-12));
    expect(load.acuteDays, 7);
    expect(load.chronicDays, 28);
  });

  test('ignores today, the future, older days and negative values', () {
    final load = activityLoad([
      ...days(range(1, 28), 300),
      ...days([0, -1, 29, 40], 5000),
      (date: today.addDays(-30), value: -10),
    ], today: today)!;
    expect(load.ratio, 1);
    expect(load.chronicDays, 28);
  });

  test('needs four of the last seven days', () {
    final enough = [...days(range(1, 4), 500), ...days(range(8, 17), 500)];
    expect(activityLoad(enough, today: today), isNotNull);
    final short = [...days(range(1, 3), 500), ...days(range(8, 18), 500)];
    expect(activityLoad(short, today: today), isNull);
  });

  test('needs fourteen of the last twenty eight days', () {
    final enough = [...days(range(1, 4), 500), ...days(range(8, 17), 500)];
    expect(activityLoad(enough, today: today)!.chronicDays, 14);
    final short = [...days(range(1, 4), 500), ...days(range(8, 16), 500)];
    expect(activityLoad(short, today: today), isNull);
  });

  test('no data, a single day or an all zero month gives no ratio', () {
    expect(activityLoad(const [], today: today), isNull);
    expect(activityLoad(days([1], 500), today: today), isNull);
    expect(activityLoad(days(range(1, 28), 0), today: today), isNull);
  });
}
