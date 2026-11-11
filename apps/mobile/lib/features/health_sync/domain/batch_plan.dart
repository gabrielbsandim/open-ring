import 'package:meta/meta.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';

@immutable
final class TimeWindow {
  const new(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

const _tick = Duration(milliseconds: 1);

// Ranges tile [from, to] so a replace also clears records drift no longer
// holds; excluded windows belong to another writer and are never covered.
List<HealthWriteBatch> planBatches({
  required HealthRecordKind kind,
  required int version,
  required DateTime from,
  required DateTime to,
  required List<HealthEntry> entries,
  required int batchSize,
  List<TimeWindow> excluded = const [],
}) {
  final sorted = [...entries]..sort((a, b) => a.start.compareTo(b.start));
  final low = _earliest(from, sorted.isEmpty ? null : sorted.first.start);
  final high = _latest(to, [for (final e in sorted) e.end]).add(_tick);
  final batches = <HealthWriteBatch>[];
  for (final segment in _segments(low, high, excluded)) {
    final inside = [
      for (final entry in sorted)
        if (!entry.start.isBefore(segment.start) &&
            entry.start.isBefore(segment.end))
          entry,
    ];
    batches.addAll(
      _chunk(inside, batchSize, segment).map(
        (chunk) => HealthWriteBatch(
          kind: kind,
          from: chunk.window.start,
          to: chunk.window.end,
          version: version,
          entries: chunk.entries,
        ),
      ),
    );
  }
  return batches;
}

List<TimeWindow> _segments(
  DateTime low,
  DateTime high,
  List<TimeWindow> excluded,
) {
  final holes = [
    for (final window in excluded)
      if (window.start.isBefore(high) && !window.end.isBefore(low))
        TimeWindow(window.start, window.end.add(_tick)),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final segments = <TimeWindow>[];
  var cursor = low;
  for (final hole in holes) {
    if (hole.start.isAfter(cursor)) {
      segments.add(TimeWindow(cursor, hole.start));
    }
    if (hole.end.isAfter(cursor)) cursor = hole.end;
  }
  if (cursor.isBefore(high)) segments.add(TimeWindow(cursor, high));
  return segments;
}

Iterable<({TimeWindow window, List<HealthEntry> entries})> _chunk(
  List<HealthEntry> entries,
  int size,
  TimeWindow segment,
) sync* {
  if (entries.isEmpty) {
    yield (window: segment, entries: const []);
    return;
  }
  for (var i = 0; i < entries.length; i += size) {
    final next = i + size;
    final last = next >= entries.length;
    yield (
      window: TimeWindow(
        i == 0 ? segment.start : entries[i].start,
        last ? segment.end : entries[next].start,
      ),
      entries: entries.sublist(i, last ? entries.length : next),
    );
  }
}

DateTime _earliest(DateTime a, DateTime? b) =>
    b != null && b.isBefore(a) ? b : a;

DateTime _latest(DateTime a, Iterable<DateTime> others) =>
    others.fold(a, (latest, other) => other.isAfter(latest) ? other : latest);
