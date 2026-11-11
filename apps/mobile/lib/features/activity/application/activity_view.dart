import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';

typedef ActivityWeekDay = ({LocalDate date, DailyActivity? activity});

typedef HourPeak = ({int hour, int steps});

List<int?> hourlySteps(LocalDate date, Iterable<ActivitySlot> slots) {
  final hours = List<int?>.filled(Duration.hoursPerDay, null);
  for (final slot in slots) {
    if (slot.date != date) continue;
    hours[slot.localHour] = (hours[slot.localHour] ?? 0) + slot.steps;
  }
  return List.unmodifiable(hours);
}

@immutable
final class ActivityDayView {
  new({
    required this.date,
    required this.stepGoal,
    required this.today,
    required List<int?> hourlySteps,
    required List<ActivityWeekDay> week,
  }) : hourlySteps = List.unmodifiable(hourlySteps),
       week = List.unmodifiable(week);

  final LocalDate date;
  final int stepGoal;
  final DailyActivity? today;
  final List<int?> hourlySteps;
  final List<ActivityWeekDay> week;

  bool get isEmpty => today == null && week.every((d) => d.activity == null);

  double get goalShare {
    final steps = today?.steps ?? 0;
    if (stepGoal <= 0) return 0;
    return steps / stepGoal;
  }

  HourPeak? get peak {
    HourPeak? best;
    for (var hour = 0; hour < hourlySteps.length; hour++) {
      final steps = hourlySteps[hour] ?? 0;
      if (steps <= 0 || (best != null && best.steps >= steps)) continue;
      best = (hour: hour, steps: steps);
    }
    return best;
  }
}
