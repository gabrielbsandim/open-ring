import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';

@immutable
final class WeightSummary {
  const new({
    required this.last,
    required this.daily,
    required this.line,
    required this.rate,
  });

  final WeighIn last;
  final List<DailyValue> daily;
  final List<DailyValue> line;
  final WeightRate rate;

  double get trend => line.last.value;
}

DailyValue _onItsDay(WeighIn entry) => (
  date: LocalDate.fromInstant(entry.at, Duration(minutes: entry.offsetMinutes)),
  value: entry.kilograms,
);

final weightSummaryProvider = FutureProvider<WeightSummary?>((ref) async {
  final entries = await ref.watch(weighInsProvider.future);
  if (entries.isEmpty) return null;
  final days = entries.map(_onItsDay).toList();
  return WeightSummary(
    last: entries.first,
    daily: dailyWeights(days),
    line: weightTrend(days),
    rate: weightRate(days, today: ref.watch(currentDateProvider)),
  );
});
