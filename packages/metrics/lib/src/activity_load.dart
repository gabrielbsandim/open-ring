import 'package:metrics/src/baseline.dart';
import 'package:metrics/src/local_date.dart';

const acuteLoadDays = 7;
const chronicLoadDays = 28;
const minAcuteLoadDays = 4;
const minChronicLoadDays = 14;

final class ActivityLoad {
  const new({
    required this.acute,
    required this.chronic,
    required this.acuteDays,
    required this.chronicDays,
  });

  final double acute;
  final double chronic;
  final int acuteDays;
  final int chronicDays;

  double get ratio => acute / chronic;
}

ActivityLoad? activityLoad(
  Iterable<DailyValue> dailyActiveKilocalories, {
  required LocalDate today,
}) {
  final byDate = <LocalDate, double>{};
  for (final d in dailyActiveKilocalories) {
    final age = today.daysSince(d.date);
    if (age < 1 || age > chronicLoadDays) continue;
    if (!d.value.isFinite || d.value < 0) continue;
    byDate[d.date] = d.value;
  }
  final acute = [
    for (final e in byDate.entries)
      if (today.daysSince(e.key) <= acuteLoadDays) e.value,
  ];
  if (acute.length < minAcuteLoadDays) return null;
  if (byDate.length < minChronicLoadDays) return null;
  final chronic = byDate.values.reduce((a, b) => a + b) / byDate.length;
  if (chronic <= 0) return null;
  return ActivityLoad(
    acute: acute.reduce((a, b) => a + b) / acute.length,
    chronic: chronic,
    acuteDays: acute.length,
    chronicDays: byDate.length,
  );
}
