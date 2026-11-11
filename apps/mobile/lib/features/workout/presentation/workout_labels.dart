import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/workout/application/workout_state.dart';
import 'package:open_ring/features/workout/domain/live_heart_rate_source.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/domain/workout_analysis.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

const goodFixAccuracyMeters = 10.0;
const gpsLostAfter = Duration(seconds: 15);

String workoutHealthPlatform() => switch (defaultTargetPlatform) {
  TargetPlatform.iOS || TargetPlatform.macOS => 'Apple Health',
  _ => 'Health Connect',
};

extension WorkoutTypeLabels on WorkoutType {
  String label(AppLocalizations l10n) => switch (this) {
    WorkoutType.running => l10n.workoutTypeRunning,
    WorkoutType.walking => l10n.workoutTypeWalking,
    WorkoutType.cycling => l10n.workoutTypeCycling,
    WorkoutType.hiking => l10n.workoutTypeHiking,
    WorkoutType.strength => l10n.workoutTypeStrength,
    WorkoutType.treadmill => l10n.workoutTypeTreadmill,
    WorkoutType.stationaryBike => l10n.workoutTypeStationaryBike,
    WorkoutType.elliptical => l10n.workoutTypeElliptical,
    WorkoutType.yoga => l10n.workoutTypeYoga,
    WorkoutType.other => l10n.workoutTypeOther,
  };

  IconData get icon => switch (this) {
    WorkoutType.running => Icons.directions_run_rounded,
    WorkoutType.walking => Icons.directions_walk_rounded,
    WorkoutType.cycling => Icons.directions_bike_rounded,
    WorkoutType.hiking => Icons.hiking_rounded,
    WorkoutType.strength => Icons.fitness_center_rounded,
    WorkoutType.treadmill => Icons.directions_run_outlined,
    WorkoutType.stationaryBike => Icons.pedal_bike_rounded,
    WorkoutType.elliptical => Icons.sports_gymnastics_rounded,
    WorkoutType.yoga => Icons.self_improvement_rounded,
    WorkoutType.other => Icons.more_horiz_rounded,
  };

  bool get showsSpeed => this == WorkoutType.cycling;

  String recorded(AppLocalizations l10n) => switch (this) {
    WorkoutType.running ||
    WorkoutType.walking ||
    WorkoutType.hiking => l10n.workoutRecordedOutdoor,
    WorkoutType.cycling => l10n.workoutRecordedCycling,
    WorkoutType.yoga => l10n.workoutRecordedYoga,
    WorkoutType.other => l10n.workoutRecordedOptional,
    WorkoutType.strength ||
    WorkoutType.treadmill ||
    WorkoutType.stationaryBike ||
    WorkoutType.elliptical => l10n.workoutRecordedOther,
  };

  String gpsNote(AppLocalizations l10n, {required bool gps}) {
    if (gps) return l10n.workoutGpsOnNote(workoutHealthPlatform());
    return switch (location) {
      WorkoutLocation.outdoor => l10n.workoutGpsOffOutdoorNote,
      WorkoutLocation.optional => l10n.workoutGpsOptionalNote,
      WorkoutLocation.indoor => l10n.workoutGpsOffNote,
    };
  }

  static WorkoutType parse(String? name) => WorkoutType.values.firstWhere(
    (type) => type.name == name,
    orElse: () => WorkoutType.running,
  );
}

extension WorkoutHealthLabels on WorkoutHealthStatus {
  String label(AppLocalizations l10n) => switch (this) {
    WorkoutHealthStatus.sent => l10n.workoutHealthSent(workoutHealthPlatform()),
    WorkoutHealthStatus.pending => l10n.workoutHealthPending(
      workoutHealthPlatform(),
    ),
    WorkoutHealthStatus.failed => l10n.workoutHealthFailed(
      workoutHealthPlatform(),
    ),
    WorkoutHealthStatus.notQueued => l10n.workoutHealthLocal,
  };

  Color color(AppColors colors) => switch (this) {
    WorkoutHealthStatus.sent => colors.activity,
    WorkoutHealthStatus.pending => colors.textSecondary,
    WorkoutHealthStatus.failed => colors.heart,
    WorkoutHealthStatus.notQueued => colors.textLabel,
  };
}

String zoneName(AppLocalizations l10n, int zone) => switch (zone) {
  1 => l10n.workoutZone1,
  2 => l10n.workoutZone2,
  3 => l10n.workoutZone3,
  4 => l10n.workoutZone4,
  _ => l10n.workoutZone5,
};

extension WorkoutFormat on MetricFormat {
  String elapsedClock(Duration value) {
    final seconds = value.inSeconds;
    return '${_two(seconds ~/ 3600)}:${_two(seconds ~/ 60 % 60)}:'
        '${_two(seconds % 60)}';
  }

  String workoutDay(DateTime start, Duration utcOffset, LocalDate today) {
    final day = LocalDate.fromInstant(start, utcOffset);
    if (day == today) return l10n.workoutDayToday;
    if (day == today.addDays(-1)) return l10n.workoutDayYesterday;
    return date(day);
  }

  String optionalInteger(num? value) {
    if (value == null) return l10n.workoutNoValue;
    return integer(value);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

extension WorkoutUnits on UnitFormat {
  String paceOrSpeed(WorkoutType type, Duration? perKilometre) =>
      type.showsSpeed ? speed(perKilometre) : pace(perKilometre);

  String paceOrSpeedUnit(WorkoutType type) =>
      type.showsSpeed ? speedUnit : paceUnit;

  List<WorkoutSplit> splitsOf(FinishedWorkout workout) =>
      distanceSplits(workout, splitMeters: distanceUnitMeters);

  String get splitsTitle =>
      select(l10n.workoutSplitsTitle, l10n.workoutSplitsTitleMi);

  String get splitLabel => select(l10n.workoutSplitKm, l10n.workoutSplitMi);

  String splitNumber(WorkoutSplit split) {
    if (!split.partial) return format.integer(split.number);
    return format.decimal(
      (split.number - 1) + split.distanceMeters / split.splitMeters,
      digits: 2,
    );
  }

  String splitLastNote(WorkoutSplit split) => select(
    l10n.workoutSplitLastNote,
    l10n.workoutSplitLastNoteMi,
  )(distance(split.distanceMeters));

  String splitSemantics(WorkoutSplit split) {
    final number = splitNumber(split);
    final splitPace = pace(split.pace);
    final bpm = split.averageHeartRate;
    if (bpm == null) {
      return select(
        l10n.workoutSplitSemanticsNoHeart,
        l10n.workoutSplitSemanticsNoHeartMi,
      )(number, splitPace);
    }
    return select(l10n.workoutSplitSemantics, l10n.workoutSplitSemanticsMi)(
      number,
      splitPace,
      format.integer(bpm),
    );
  }

  String mapSemantics(double meters) => select(
    l10n.workoutMapSemantics,
    l10n.workoutMapSemanticsMi,
  )(distance(meters));

  String routeSemantics(double? meters) => select(
    l10n.workoutRouteSemantics,
    l10n.workoutRouteSemanticsMi,
  )(distance(meters));

  String gpsAccuracy(double meters) => select(
    l10n.workoutGpsAccuracy,
    l10n.workoutGpsAccuracyFeet,
  )(length(meters));

  String routeAccuracy(double meters) => select(
    l10n.workoutRouteAccuracy,
    l10n.workoutRouteAccuracyFeet,
  )(length(meters));
}

LocationNotice workoutLocationNotice(AppLocalizations l10n) => LocationNotice(
  title: l10n.workoutNotificationTitle,
  text: l10n.workoutNotificationText,
  channel: l10n.workoutNotificationChannel,
);

enum GpsQuality {
  good,
  fair,
  searching,
  lost,
  off;

  String label(AppLocalizations l10n) => switch (this) {
    GpsQuality.good => l10n.workoutGpsGood,
    GpsQuality.fair => l10n.workoutGpsFair,
    GpsQuality.searching => l10n.workoutGpsSearching,
    GpsQuality.lost => l10n.workoutGpsLost,
    GpsQuality.off => l10n.workoutGpsOff,
  };

  Color color(AppColors colors) => switch (this) {
    GpsQuality.good => colors.activity,
    GpsQuality.fair || GpsQuality.searching => colors.stress,
    GpsQuality.lost || GpsQuality.off => colors.heart,
  };

  bool get showsAccuracy => this == good || this == fair;
}

GpsQuality gpsQualityOf({
  required WorkoutStatus status,
  required DateTime now,
  LocationProblem? problem,
  TrackPoint? last,
}) {
  if (problem != null) return GpsQuality.off;
  if (last == null) return GpsQuality.searching;
  final stale = now.difference(last.at) > gpsLostAfter;
  if (status == WorkoutStatus.running && stale) return GpsQuality.lost;
  final accuracy = last.accuracyMeters ?? double.infinity;
  if (accuracy <= goodFixAccuracyMeters) return GpsQuality.good;
  return GpsQuality.fair;
}

String locationProblemMessage(AppLocalizations l10n, LocationProblem problem) =>
    switch (problem) {
      LocationProblem.denied ||
      LocationProblem.deniedForever => l10n.workoutGpsDeniedBody,
      LocationProblem.serviceDisabled => l10n.workoutGpsServiceOffBody,
      LocationProblem.failed => l10n.workoutGpsFailedBody,
    };

enum RingLink {
  streaming,
  waiting,
  paused,
  noRing,
  busy,
  lost,
  stalled,
  released;

  String label(AppLocalizations l10n) => switch (this) {
    RingLink.streaming => l10n.workoutLinkStreaming,
    RingLink.waiting => l10n.workoutLinkWaiting,
    RingLink.paused => l10n.workoutLinkPaused,
    RingLink.noRing => l10n.workoutLinkNoRing,
    RingLink.busy => l10n.workoutLinkBusy,
    RingLink.lost => l10n.workoutLinkLost,
    RingLink.stalled => l10n.workoutLinkHeartRateLost,
    RingLink.released => l10n.workoutLinkReleased,
  };

  Color color(AppColors colors) => switch (this) {
    RingLink.streaming => colors.activity,
    RingLink.waiting => colors.stress,
    RingLink.paused || RingLink.released => colors.textLabel,
    RingLink.noRing ||
    RingLink.busy ||
    RingLink.lost ||
    RingLink.stalled => colors.heart,
  };

  bool get failed => this == noRing || reconnects;

  bool get reconnects => this == busy || this == lost || this == stalled;

  String? heartMessage(AppLocalizations l10n) => switch (this) {
    RingLink.noRing => l10n.workoutHeartNoRing,
    RingLink.busy => l10n.workoutHeartBusy,
    RingLink.lost => l10n.workoutHeartLost,
    RingLink.stalled => l10n.workoutHeartStalled,
    RingLink.streaming ||
    RingLink.waiting ||
    RingLink.paused ||
    RingLink.released => null,
  };
}

RingLink ringLinkOf(WorkoutState state) {
  final problem = state.heartRateProblem;
  if (problem != null) {
    return switch (problem) {
      HeartRateProblem.noRing => RingLink.noRing,
      HeartRateProblem.busy => RingLink.busy,
      HeartRateProblem.unreachable => RingLink.lost,
    };
  }
  if (state.heartRateStalled) return RingLink.stalled;
  final streaming = state.snapshot?.currentHeartRate != null;
  return switch (state.status) {
    WorkoutStatus.running => streaming ? RingLink.streaming : RingLink.waiting,
    WorkoutStatus.paused => RingLink.paused,
    WorkoutStatus.idle ||
    WorkoutStatus.finished ||
    WorkoutStatus.discarded => RingLink.released,
  };
}

TrackPoint? lastPointOf(WorkoutRoute route) => route.segments.lastOrNull?.last;
