import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_score_view.dart';
import 'package:open_ring/features/today/application/today_view.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';

enum WidgetDayScoreKind { full, partial, firstDays, noScore, afterMidnight }

enum WidgetWeightDirection { falling, rising, steady, building }

enum WidgetGoalsState { running, review, paused, hold, base, recovery }

@immutable
final class WidgetDayScore {
  const new({
    required this.kind,
    required this.coverage,
    this.score,
    this.band,
    this.pillarPoints,
    this.asOf,
    this.gap,
  });

  final WidgetDayScoreKind kind;
  final int? score;
  final DayScoreBand? band;
  final int coverage;
  final List<double?>? pillarPoints;
  final DateTime? asOf;
  final DayScoreGap? gap;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'score': score,
    'band': band?.name,
    'coverage': coverage,
    'pillarPoints': pillarPoints,
    'asOfMs': asOf?.millisecondsSinceEpoch,
    'gap': gap?.name,
  };
}

@immutable
final class WidgetWeight {
  const new({required this.direction, this.trendKilograms});

  final double? trendKilograms;
  final WidgetWeightDirection direction;

  Map<String, Object?> toJson({required bool hideNumbers}) => {
    'trendKilograms': hideNumbers ? null : trendKilograms,
    'direction': direction.name,
  };
}

@immutable
final class WidgetEnergy {
  const new({required this.lowKcal, required this.highKcal});

  final int lowKcal;
  final int highKcal;

  Map<String, Object?> toJson() => {'lowKcal': lowKcal, 'highKcal': highKcal};
}

@immutable
final class WidgetEffort {
  const new({
    required this.points,
    required this.targetPoints,
    required this.strengthDays,
    required this.strengthTarget,
  });

  final int points;
  final int targetPoints;
  final int strengthDays;
  final int strengthTarget;

  Map<String, Object?> toJson() => {
    'points': points,
    'targetPoints': targetPoints,
    'strengthDays': strengthDays,
    'strengthTarget': strengthTarget,
  };
}

@immutable
final class WidgetGoalLever {
  const new({
    required this.kind,
    required this.target,
    required this.achieved,
    required this.goal,
    this.days,
  });

  final LeverKind kind;
  final int target;
  final int achieved;
  final int goal;
  final List<LeverDayMark>? days;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'target': target,
    'achieved': achieved,
    'goal': goal,
    'days': days == null ? null : [for (final day in days!) day.name],
  };
}

@immutable
final class WidgetGoals {
  const new({
    required this.state,
    required this.monday,
    required this.sunday,
    this.weekNumber,
    this.blockWeeks,
    this.maintenance = false,
    this.levers = const [],
  });

  final WidgetGoalsState state;
  final LocalDate monday;
  final LocalDate sunday;
  final int? weekNumber;
  final int? blockWeeks;
  final bool maintenance;
  final List<WidgetGoalLever> levers;

  Map<String, Object?> toJson() => {
    'state': state.name,
    'monday': monday.iso,
    'sunday': sunday.iso,
    'weekNumber': weekNumber,
    'blockWeeks': blockWeeks,
    'maintenance': maintenance,
    'levers': [for (final lever in levers) lever.toJson()],
  };
}

@immutable
final class WidgetSnapshot {
  const new({
    required this.date,
    required this.freshness,
    required this.stepGoal,
    this.syncedAt,
    this.readiness,
    this.restingHeartRate,
    this.hrv,
    this.baselineNights,
    this.sleepMinutes,
    this.sleepScore,
    this.steps,
    this.heartRateMean,
    this.heartRateMin,
    this.heartRateMax,
    this.spo2,
    this.stress,
    this.batteryPercent,
    this.batteryCharging,
    this.lastWorkout,
    this.enabledModules = const {},
    this.hideNumbers = false,
    this.dayScore,
    this.weight,
    this.energy,
    this.effort,
    this.goals,
  });

  static const version = 2;

  final LocalDate date;
  final SyncFreshness freshness;
  final DateTime? syncedAt;
  final int stepGoal;
  final int? readiness;
  final int? restingHeartRate;
  final int? hrv;
  final int? baselineNights;
  final int? sleepMinutes;
  final int? sleepScore;
  final int? steps;
  final int? heartRateMean;
  final int? heartRateMin;
  final int? heartRateMax;
  final int? spo2;
  final int? stress;
  final int? batteryPercent;
  final bool? batteryCharging;
  final WorkoutEntry? lastWorkout;
  final Set<ModuleId> enabledModules;
  final bool hideNumbers;
  final WidgetDayScore? dayScore;
  final WidgetWeight? weight;
  final WidgetEnergy? energy;
  final WidgetEffort? effort;
  final WidgetGoals? goals;

  bool get paired => freshness != SyncFreshness.unpaired;

  bool get hasHealthData => [
    readiness,
    restingHeartRate,
    hrv,
    sleepMinutes,
    sleepScore,
    steps,
    heartRateMean,
    spo2,
    stress,
  ].any((value) => value != null);

  Map<String, Object?> toJson() => {
    'version': version,
    'date': date.iso,
    'paired': paired,
    'syncedAtMs': syncedAt?.millisecondsSinceEpoch,
    'staleAfterMs': staleSyncAfter.inMilliseconds,
    'stepGoal': stepGoal,
    'readiness': readiness,
    'restingHeartRate': restingHeartRate,
    'hrv': hrv,
    'baselineNights': baselineNights,
    'sleepMinutes': sleepMinutes,
    'sleepScore': sleepScore,
    'steps': steps,
    'heartRateMean': heartRateMean,
    'heartRateMin': heartRateMin,
    'heartRateMax': heartRateMax,
    'spo2': spo2,
    'stress': stress,
    'batteryPercent': batteryPercent,
    'batteryCharging': batteryCharging,
    'lastWorkout': switch (lastWorkout) {
      null => null,
      final workout => {
        'type': workout.type.name,
        'startMs': workout.start.millisecondsSinceEpoch,
        'elapsedSeconds': workout.elapsed.inSeconds,
        'distanceMeters': switch (workout) {
          WorkoutListItem(:final distanceMeters) => distanceMeters,
          ImportedWorkout() => null,
        },
      },
    },
    'enabledModules': [for (final id in enabledModules) id.name]..sort(),
    'hideNumbers': hideNumbers,
    'dayScore': dayScore?.toJson(),
    'weight': weight?.toJson(hideNumbers: hideNumbers),
    'energy': hideNumbers ? null : energy?.toJson(),
    'effort': effort?.toJson(),
    'goals': goals?.toJson(),
  };
}
