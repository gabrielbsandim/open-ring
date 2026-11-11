import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';

typedef SleepBreak = ({DateTime start, Duration duration, Duration utcOffset});

@immutable
final class SleepDayView {
  const new({required this.date, required this.night, required this.score});

  factory of(
    LocalDate date,
    SleepNight? night, {
    required Duration goal,
    required bool remMeasured,
  }) => SleepDayView(
    date: date,
    night: night,
    score: sleepScore(night, goal: goal, remMeasured: remMeasured),
  );

  final LocalDate date;
  final SleepNight? night;
  final ScoreResult<SleepFactor> score;

  int? get scoreValue => switch (score) {
    Scored(:final value) => value,
    InsufficientData() => null,
  };

  int get stretches => (night?.gaps.length ?? 0) + 1;

  SleepBreak? get splitBreak {
    final night = this.night;
    if (night == null || night.gaps.isEmpty) return null;
    final offset = night.spans.last.utcOffset;
    final bridged = night.awakenings.where((a) => a.bridgesGap).toList();
    if (bridged.isEmpty) {
      final gap = night.gaps.reduce((a, b) => a.duration >= b.duration ? a : b);
      return (start: gap.start, duration: gap.duration, utcOffset: offset);
    }
    final longest = bridged.reduce((a, b) => a.duration >= b.duration ? a : b);
    return (
      start: longest.start,
      duration: longest.duration,
      utcOffset: offset,
    );
  }
}

@immutable
final class SleepWeekView {
  new({
    required List<SleepDayView> days,
    required this.goal,
    required this.remMeasured,
  }) : days = List.unmodifiable(days);

  final List<SleepDayView> days;
  final Duration goal;
  final bool remMeasured;

  SleepDayView get latest => days.last;

  bool get isEmpty => days.every((d) => d.night == null);
}
