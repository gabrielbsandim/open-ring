import 'package:meta/meta.dart';
import 'package:ring_driver/ring_driver.dart';

@immutable
final class SleepSessionSpan {
  new(List<SleepSegment> segments)
    : assert(segments.isNotEmpty, 'A session needs at least one segment.'),
      segments = List.unmodifiable(segments);

  static const maxGap = Duration(hours: 1);

  final List<SleepSegment> segments;

  DateTime get start => segments.first.start;

  DateTime get end => segments.last.end;

  static List<SleepSessionSpan> group(Iterable<SleepSegment> segments) {
    final sorted = [...segments]..sort((a, b) => a.start.compareTo(b.start));
    final sessions = <List<SleepSegment>>[];
    for (final segment in sorted) {
      final current = sessions.isEmpty ? null : sessions.last;
      if (current == null ||
          segment.start.difference(current.last.end) > maxGap) {
        sessions.add([segment]);
        continue;
      }
      current.add(segment);
    }
    return [for (final session in sessions) SleepSessionSpan(session)];
  }
}
