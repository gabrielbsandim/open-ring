import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';

@immutable
final class WeightSummary {
  const new({required this.last, required this.trend, required this.rate});

  final WeighIn last;
  final double trend;
  final WeightRate rate;
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
    trend: weightTrend(days).last.value,
    rate: weightRate(days, today: ref.watch(currentDateProvider)),
  );
});
