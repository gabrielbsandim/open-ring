import 'package:meta/meta.dart';

@immutable
final class WriteSummary {
  const new({this.count = 0, this.from, this.to});

  static const empty = WriteSummary();

  final int count;
  final DateTime? from;
  final DateTime? to;

  WriteSummary include(int rows, DateTime start, DateTime end) {
    if (rows == 0) return this;
    return WriteSummary(
      count: count + rows,
      from: _earliest(from, start),
      to: _latest(to, end),
    );
  }

  WriteSummary cover(DateTime start, DateTime end) {
    if (count == 0) return this;
    return WriteSummary(
      count: count,
      from: _earliest(from, start),
      to: _latest(to, end),
    );
  }

  WriteSummary merge(WriteSummary other) {
    final (otherFrom, otherTo) = (other.from, other.to);
    if (otherFrom == null || otherTo == null) return this;
    return include(other.count, otherFrom, otherTo);
  }

  static DateTime _earliest(DateTime? current, DateTime candidate) =>
      current == null || candidate.isBefore(current) ? candidate : current;

  static DateTime _latest(DateTime? current, DateTime candidate) =>
      current == null || candidate.isAfter(current) ? candidate : current;
}

Future<WriteSummary> writeEach<T>(
  Iterable<T> items, {
  required DateTime Function(T item) start,
  required DateTime Function(T item) end,
  required Future<Object?> Function(T item) write,
}) async {
  var summary = WriteSummary.empty;
  for (final item in items) {
    if (await write(item) == null) continue;
    summary = summary.include(1, start(item), end(item));
  }
  return summary;
}
