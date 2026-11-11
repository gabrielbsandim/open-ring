import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/sleep/domain/imported_sleep_reader.dart';
import 'package:open_ring/features/sleep/domain/sleep_history_reader.dart';

// Each source is stitched on its own and a date takes the night of the first
// source in the order that has one, so two sources are never merged.
Map<LocalDate, SleepNight> nightsBySourcePriority(
  Map<String, List<SleepSpan>> spansBySource,
  List<String> priority,
) {
  final chosen = <LocalDate, SleepNight>{};
  for (final source in priority) {
    final spans = spansBySource[source] ?? const <SleepSpan>[];
    for (final MapEntry(key: date, value: night) in mainNightByDate(
      stitchSleep(spans),
    ).entries) {
      chosen.putIfAbsent(date, () => night);
    }
  }
  final dates = chosen.keys.toList()..sort((a, b) => a.compareTo(b));
  return {for (final date in dates) date: chosen[date]!};
}

Future<Map<LocalDate, SleepNight>> readSleepNights({
  required SleepHistoryReader ring,
  required ImportedSleepReader imported,
  required DateTime from,
  required DateTime to,
}) async {
  final (ringSpans, other) = await (
    ring.sleepSpans(from: from, to: to),
    imported.importedSleep(from: from, to: to),
  ).wait;
  return nightsBySourcePriority({
    ...other.spans,
    ringSource: ringSpans,
  }, other.priority);
}
