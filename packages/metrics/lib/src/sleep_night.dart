import 'package:metrics/src/local_date.dart';

enum SleepPhase { light, deep, rem, awake }

final class SleepSpan {
  const new({
    required this.start,
    required this.end,
    required this.phase,
    required this.utcOffset,
  });

  final DateTime start;
  final DateTime end;
  final SleepPhase phase;
  final Duration utcOffset;

  Duration get duration => end.difference(start);

  bool get isAsleep => phase != SleepPhase.awake;

  SleepSpan _from(DateTime newStart) =>
      SleepSpan(start: newStart, end: end, phase: phase, utcOffset: utcOffset);
}

typedef SleepGap = ({DateTime start, Duration duration});

final class SleepAwakening {
  const new({
    required this.start,
    required this.duration,
    required this.bridgesGap,
  });

  final DateTime start;
  final Duration duration;
  final bool bridgesGap;
}

const defaultMaxStitchGap = Duration(minutes: 60);

final class SleepNight {
  new(List<SleepSpan> spans) : spans = List.unmodifiable(spans) {
    if (spans.isEmpty) {
      throw ArgumentError.value(spans, 'spans', 'must not be empty');
    }
  }

  final List<SleepSpan> spans;

  DateTime get start => spans.first.start;

  DateTime get end => spans.last.end;

  LocalDate get date => LocalDate.fromInstant(end, spans.last.utcOffset);

  Duration get timeInBed => end.difference(start);

  late final Duration asleep = spans
      .where((s) => s.isAsleep)
      .fold(Duration.zero, (sum, s) => sum + s.duration);

  Duration get awake => timeInBed - asleep;

  double get efficiency => asleep.inSeconds / timeInBed.inSeconds;

  late final List<SleepGap> gaps = [
    for (var i = 1; i < spans.length; i++)
      if (spans[i].start.isAfter(spans[i - 1].end))
        (
          start: spans[i - 1].end,
          duration: spans[i].start.difference(spans[i - 1].end),
        ),
  ];

  DateTime? get sleepOnset {
    for (final s in spans) {
      if (s.isAsleep) return s.start;
    }
    return null;
  }

  Duration? get latency => sleepOnset?.difference(start);

  Duration timeIn(SleepPhase phase) => switch (phase) {
    SleepPhase.awake => awake,
    _ =>
      spans
          .where((s) => s.phase == phase)
          .fold(Duration.zero, (sum, s) => sum + s.duration),
  };

  double? share(SleepPhase phase) {
    if (phase == SleepPhase.awake) {
      return awake.inSeconds / timeInBed.inSeconds;
    }
    if (asleep == Duration.zero) return null;
    return timeIn(phase).inSeconds / asleep.inSeconds;
  }

  late final List<SleepAwakening> awakenings = _awakenings();

  Duration get wakeAfterSleepOnset =>
      awakenings.fold(Duration.zero, (sum, a) => sum + a.duration);

  List<SleepAwakening> _awakenings() {
    final blocks = <_Block>[];
    for (final s in spans) {
      final previous = blocks.isEmpty ? null : blocks.last.end;
      if (previous != null && s.start.isAfter(previous)) {
        blocks.add(_Block(previous, s.start, asleep: false, gap: true));
      }
      blocks.add(_Block(s.start, s.end, asleep: s.isAsleep, gap: false));
    }
    final first = blocks.indexWhere((b) => b.asleep);
    final last = blocks.lastIndexWhere((b) => b.asleep);
    final found = <SleepAwakening>[];
    if (first < 0) return found;
    _Run? open;
    for (final b in blocks.sublist(first, last + 1)) {
      if (!b.asleep) {
        open ??= _Run(b.start);
        open
          ..end = b.end
          ..bridgesGap = open.bridgesGap || b.gap;
        continue;
      }
      final closed = open;
      open = null;
      if (closed == null) continue;
      found.add(
        SleepAwakening(
          start: closed.start,
          duration: closed.end.difference(closed.start),
          bridgesGap: closed.bridgesGap,
        ),
      );
    }
    return found;
  }
}

final class _Block {
  const new(this.start, this.end, {required this.asleep, required this.gap});

  final DateTime start;
  final DateTime end;
  final bool asleep;
  final bool gap;
}

final class _Run {
  new(this.start) : end = start;

  final DateTime start;
  DateTime end;
  bool bridgesGap = false;
}

List<SleepNight> stitchSleep(
  Iterable<SleepSpan> spans, {
  Duration maxGap = defaultMaxStitchGap,
}) {
  if (maxGap.isNegative) {
    throw ArgumentError.value(maxGap, 'maxGap', 'must not be negative');
  }
  final sorted = spans.where((s) => s.end.isAfter(s.start)).toList()
    ..sort(_bySpanOrder);

  final nights = <SleepNight>[];
  var current = <SleepSpan>[];
  for (final s in sorted) {
    if (current.isEmpty) {
      current.add(s);
      continue;
    }
    final lastEnd = current.last.end;
    if (!s.end.isAfter(lastEnd)) continue;
    // Overlapping exports keep the earlier span, so stage time is never counted twice.
    if (s.start.isBefore(lastEnd)) {
      current.add(s._from(lastEnd));
      continue;
    }
    if (s.start.difference(lastEnd) <= maxGap) {
      current.add(s);
      continue;
    }
    nights.add(SleepNight(current));
    current = [s];
  }
  if (current.isNotEmpty) nights.add(SleepNight(current));
  return [
    for (final n in nights)
      if (n.asleep > Duration.zero) n,
  ];
}

int _bySpanOrder(SleepSpan a, SleepSpan b) {
  final start = a.start.compareTo(b.start);
  if (start != 0) return start;
  final end = b.end.compareTo(a.end);
  if (end != 0) return end;
  return a.phase.index.compareTo(b.phase.index);
}

Map<LocalDate, SleepNight> mainNightByDate(Iterable<SleepNight> nights) {
  final byDate = <LocalDate, SleepNight>{};
  for (final n in nights) {
    final kept = byDate[n.date];
    if (kept != null && kept.asleep >= n.asleep) continue;
    byDate[n.date] = n;
  }
  return byDate;
}
