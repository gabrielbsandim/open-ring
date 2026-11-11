import 'dart:math';

import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/health_sync/domain/batch_plan.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';

// Health Connect documents no sample cap per series record; this one keeps a
// record (and an insert) a few hundred KB at most, far below its call limits.
const maxSeriesSamples = 10000;

const seriesSpan = Duration(hours: 1);

int _bucket(DateTime at) => at.utcMs ~/ seriesSpan.inMilliseconds;

DateTime seriesBucketStart(DateTime at) =>
    fromUtcMs(_bucket(at) * seriesSpan.inMilliseconds);

// Buckets are fixed UTC hours, so the same samples always form the same
// records whatever span the outbox row covered.
List<HeartRateSeriesEntry> heartRateSeries(
  String device,
  Iterable<HeartRateEntry> samples, {
  List<TimeWindow> excluded = const [],
  int maxSamples = maxSeriesSamples,
}) {
  final sorted = [...samples]..sort((a, b) => a.at.compareTo(b.at));
  final groups = <List<HeartRateEntry>>[];
  HeartRateEntry? previous;
  for (final sample in sorted) {
    if (_inside(sample.at, excluded)) continue;
    final fresh =
        previous == null ||
        _separated(previous, sample, excluded) ||
        groups.last.length >= maxSamples;
    if (fresh) groups.add([]);
    groups.last.add(sample);
    previous = sample;
  }
  return [
    for (final group in groups)
      HeartRateSeriesEntry(
        id: HealthRecordId.of(
          device,
          HealthEntryType.heartRateSeries,
          group.first.at,
        ),
        start: group.first.at,
        end: group.last.at,
        samples: List.unmodifiable(group),
      ),
  ];
}

List<HeartRateSeriesEntry> workoutHeartRateSeries(
  String device, {
  required DateTime start,
  required DateTime end,
  required List<HeartRateEntry> samples,
  int maxSamples = maxSeriesSamples,
}) {
  final sorted = [...samples]..sort((a, b) => a.at.compareTo(b.at));
  final series = <HeartRateSeriesEntry>[];
  for (var i = 0; i < sorted.length; i += maxSamples) {
    final next = min(i + maxSamples, sorted.length);
    final chunk = sorted.sublist(i, next);
    final from = i == 0 ? start : chunk.first.at;
    series.add(
      HeartRateSeriesEntry(
        id: HealthRecordId.of(
          device,
          HealthEntryType.workoutHeartRateSeries,
          from,
        ),
        start: from,
        end: next == sorted.length ? end : chunk.last.at,
        samples: List.unmodifiable(chunk),
      ),
    );
  }
  return series;
}

bool _inside(DateTime at, List<TimeWindow> excluded) => excluded.any(
  (window) => !at.isBefore(window.start) && !at.isAfter(window.end),
);

bool _separated(
  HeartRateEntry previous,
  HeartRateEntry sample,
  List<TimeWindow> excluded,
) =>
    _bucket(previous.at) != _bucket(sample.at) ||
    excluded.any(
      (window) =>
          window.start.isAfter(previous.at) && !window.start.isAfter(sample.at),
    );
