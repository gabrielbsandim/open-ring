import 'dart:math';

import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/demo/domain/demo_data.dart';
import 'package:open_ring/features/ring/domain/sync_run.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:ring_driver/ring_driver.dart';

// Every value is derived from the calendar date or the sample time, never from
// a shared random sequence, so a refresh later the same day keeps the history.
final class DemoDataGenerator {
  const new({required this.now, this.days = defaultDays});

  static const defaultDays = 14;
  static const heartRateInterval = Duration(minutes: 5);
  static const hrvInterval = Duration(minutes: 30);
  static const stressInterval = Duration(minutes: 30);
  static const spo2Interval = Duration(hours: 1);
  static const bucketDuration = Duration(minutes: 15);
  static const workoutSampleInterval = Duration(seconds: 5);
  static const weightKilograms = 70.0;

  final DateTime now;
  final int days;

  DateTime get _today => DateTime(now.year, now.month, now.day);

  DemoData generate() {
    final nights = {
      for (var ago = days; ago >= -1; ago--)
        _key(_dayAgo(ago)): _night(_dayAgo(ago)),
    };
    final workouts = [
      for (final plan in _plans)
        if (plan.daysAgo <= days) _workout(plan),
    ];
    final timeline = _Timeline(nights: nights, workouts: workouts);
    final from = nights[_key(_dayAgo(days))]!.bed;
    final activity = _activity(timeline);
    final steps = {
      for (final bucket in activity)
        bucket.start.millisecondsSinceEpoch: bucket,
    };
    final heartRate = <HeartRateSample>[];
    final hrv = <HrvSample>[];
    final spo2 = <Spo2Sample>[];
    final stress = <StressSample>[];
    for (
      var at = _floor(from, heartRateInterval);
      !at.isAfter(now);
      at = at.add(heartRateInterval)
    ) {
      final moment = timeline.at(at);
      final bucket = steps[_floor(at, bucketDuration).millisecondsSinceEpoch];
      heartRate.add(HeartRateSample(at: at, bpm: _bpm(at, moment, bucket)));
      if (_onGrid(at, hrvInterval)) {
        hrv.add(HrvSample(at: at, milliseconds: _hrv(at, moment)));
      }
      if (_onGrid(at, spo2Interval)) {
        spo2.add(Spo2Sample(at: at, percent: _spo2(at, moment)));
      }
      if (_onGrid(at, stressInterval) && !moment.asleep) {
        stress.add(StressSample(at: at, level: _stress(at, moment)));
      }
    }
    return DemoData(
      pairedAt: from.subtract(const Duration(hours: 1)),
      syncedAt: now,
      battery: const BatteryStatus(percent: 76, charging: false),
      activity: activity,
      heartRate: heartRate,
      hrv: hrv,
      spo2: spo2,
      stress: stress,
      sleep: [
        for (final night in nights.values)
          if (!night.wake.isAfter(now)) ...night.segments,
      ],
      workouts: workouts,
      syncRuns: _syncRuns(),
    );
  }

  DateTime _dayAgo(int ago) =>
      DateTime(_today.year, _today.month, _today.day - ago);

  static int _key(DateTime day) => day.year * 10000 + day.month * 100 + day.day;

  static Random _random(DateTime day, int salt) =>
      Random(_key(day) + salt * 100000000);

  static int _jitter(DateTime at, int salt, int spread) =>
      Random(at.millisecondsSinceEpoch ~/ 1000 + salt).nextInt(spread * 2 + 1) -
      spread;

  static DateTime _floor(DateTime at, Duration step) {
    final minutes = at.hour * 60 + at.minute;
    final floored = minutes - minutes % step.inMinutes;
    return DateTime(at.year, at.month, at.day, floored ~/ 60, floored % 60);
  }

  static bool _onGrid(DateTime at, Duration step) =>
      (at.hour * 60 + at.minute) % step.inMinutes == 0;

  // The night that ends on the morning of [day].
  _Night _night(DateTime day) {
    final random = _random(day, 1);
    final bed = DateTime(
      day.year,
      day.month,
      day.day - 1,
      22,
      30 + random.nextInt(50),
    );
    final wake = DateTime(
      day.year,
      day.month,
      day.day,
      6,
      20 + random.nextInt(55),
    );
    return _Night(
      bed: bed,
      wake: wake,
      restingBpm: 50 + random.nextInt(6),
      hrvMs: 42 + random.nextInt(16),
      segments: _stages(bed, wake, random),
    );
  }

  static List<SleepSegment> _stages(
    DateTime bed,
    DateTime wake,
    Random random,
  ) {
    final segments = <SleepSegment>[];
    var at = bed;
    for (var cycle = 0; at.isBefore(wake); cycle++) {
      for (final (stage, minutes) in _cycle(cycle, random)) {
        if (minutes <= 0 || !at.isBefore(wake)) continue;
        final planned = at.add(Duration(minutes: minutes));
        final end = planned.isAfter(wake) ? wake : planned;
        segments.add(SleepSegment(start: at, end: end, stage: stage));
        at = end;
      }
    }
    return segments;
  }

  static List<(SleepStage, int)> _cycle(int index, Random random) => [
    (SleepStage.light, 18 + random.nextInt(16)),
    (SleepStage.deep, _deepMinutes(index, random)),
    (SleepStage.light, 10 + random.nextInt(12)),
    (SleepStage.rem, _remMinutes(index, random)),
    if (random.nextInt(10) < 4) (SleepStage.awake, 3 + random.nextInt(6)),
  ];

  static int _deepMinutes(int cycle, Random random) => switch (cycle) {
    0 => 35 + random.nextInt(14),
    1 => 22 + random.nextInt(12),
    2 => 8 + random.nextInt(10),
    _ => random.nextInt(6),
  };

  static int _remMinutes(int cycle, Random random) => switch (cycle) {
    0 => 8 + random.nextInt(8),
    1 => 15 + random.nextInt(9),
    2 => 20 + random.nextInt(10),
    _ => 25 + random.nextInt(12),
  };

  List<ActivityBucket> _activity(_Timeline timeline) {
    final buckets = <ActivityBucket>[];
    for (var ago = days; ago >= 0; ago--) {
      final day = _dayAgo(ago);
      final scale = 0.75 + _random(day, 2).nextDouble() * 0.5;
      for (
        var start = day;
        start.day == day.day;
        start = start.add(bucketDuration)
      ) {
        final end = start.add(bucketDuration);
        final moment = timeline.at(start);
        if (end.isAfter(now) || moment.asleep) continue;
        final steps = _steps(start, moment, scale);
        if (steps <= 0) continue;
        buckets.add(
          ActivityBucket(
            start: start,
            duration: bucketDuration,
            steps: steps,
            distanceMeters: (steps * 0.74).round(),
            activeKilocalories: (steps * 0.045 * 10).roundToDouble() / 10,
          ),
        );
      }
    }
    return buckets;
  }

  static int _steps(DateTime at, _Moment moment, double scale) {
    final workout = moment.workout;
    if (workout != null) return _workoutSteps(workout.type, at);
    final base = switch (at.hour) {
      7 || 8 => 260,
      12 => 220,
      17 || 18 => 300,
      9 || 10 || 11 || 13 || 14 || 15 || 16 => 70,
      19 || 20 || 21 => 60,
      _ => 15,
    };
    return max(0, (base * scale).round() + _jitter(at, 3, base ~/ 2));
  }

  static int _workoutSteps(WorkoutType type, DateTime at) => switch (type) {
    WorkoutType.treadmill => 2350 + _jitter(at, 4, 120),
    _ => 140 + _jitter(at, 4, 60),
  };

  int _bpm(DateTime at, _Moment moment, ActivityBucket? bucket) {
    final workout = moment.workout;
    if (workout != null) return _workoutBpm(workout, at);
    final night = moment.night;
    if (night != null) {
      return night.restingBpm + _stageBpm(moment.stage) + _jitter(at, 5, 2);
    }
    final hour = switch (at.hour) {
      6 || 7 || 8 => 4,
      9 || 10 || 11 => 8,
      12 || 13 || 14 || 15 || 16 || 17 => 11,
      _ => 6,
    };
    final effort = min(35, (bucket?.steps ?? 0) ~/ 12);
    return 60 + hour + effort + _jitter(at, 6, 4);
  }

  static int _stageBpm(SleepStage? stage) => switch (stage) {
    SleepStage.deep => -2,
    SleepStage.rem => 4,
    SleepStage.awake => 9,
    SleepStage.light || null => 1,
  };

  static int _hrv(DateTime at, _Moment moment) {
    final night = moment.night;
    if (moment.workout != null) return 18 + _jitter(at, 7, 4);
    if (night == null) return 31 + _jitter(at, 7, 7);
    final stage = switch (moment.stage) {
      SleepStage.deep => 9,
      SleepStage.awake => -10,
      SleepStage.rem => -3,
      SleepStage.light || null => 0,
    };
    return max(12, night.hrvMs + stage + _jitter(at, 7, 6));
  }

  static int _spo2(DateTime at, _Moment moment) {
    if (moment.asleep) return min(99, 95 + _jitter(at, 8, 2));
    return min(100, 97 + _jitter(at, 8, 1));
  }

  static int _stress(DateTime at, _Moment moment) {
    if (moment.workout != null) return 62 + _jitter(at, 9, 8);
    final afternoon = at.hour >= 13 && at.hour < 18 ? 14 : 0;
    return (28 + afternoon + _jitter(at, 9, 12)).clamp(5, 95);
  }

  static const _plans = [
    _WorkoutPlan(
      type: WorkoutType.treadmill,
      daysAgo: 2,
      hour: 18,
      minute: 10,
      minutes: 32,
    ),
    _WorkoutPlan(
      type: WorkoutType.strength,
      daysAgo: 5,
      hour: 17,
      minute: 30,
      minutes: 45,
    ),
  ];

  FinishedWorkout _workout(_WorkoutPlan plan) {
    final day = _dayAgo(plan.daysAgo);
    final start = DateTime(
      day.year,
      day.month,
      day.day,
      plan.hour,
      plan.minute,
    );
    final elapsed = Duration(minutes: plan.minutes);
    final end = start.add(elapsed);
    final samples = <BpmSample>[
      for (var at = start; at.isBefore(end); at = at.add(workoutSampleInterval))
        (at: at, bpm: _curve(plan, at.difference(start), at)),
    ];
    final beats = [for (final sample in samples) sample.bpm];
    final hours = elapsed.inSeconds / Duration.secondsPerHour;
    return FinishedWorkout(
      type: plan.type,
      start: start,
      end: end,
      elapsed: elapsed,
      heartRate: samples,
      route: WorkoutRoute(segments: const []),
      pauses: const [],
      activeKilocalories: (plan.type.met * weightKilograms * hours)
          .roundToDouble(),
      averageHeartRate: (beats.reduce((a, b) => a + b) / beats.length).round(),
      maxHeartRate: beats.reduce(max),
    );
  }

  static int _workoutBpm(FinishedWorkout workout, DateTime at) {
    final plan = _plans.firstWhere((p) => p.type == workout.type);
    return _curve(plan, at.difference(workout.start), at);
  }

  static int _curve(_WorkoutPlan plan, Duration elapsed, DateTime at) {
    final seconds = elapsed.inSeconds;
    final total = plan.minutes * 60;
    return switch (plan.type) {
      WorkoutType.treadmill => _runBpm(seconds, total) + _jitter(at, 10, 3),
      _ => _setBpm(seconds) + _jitter(at, 10, 4),
    };
  }

  static int _runBpm(int seconds, int total) {
    const warmUp = 300;
    const coolDown = 240;
    if (seconds < warmUp) return 98 + 50 * seconds ~/ warmUp;
    if (seconds > total - coolDown) {
      return 152 - 36 * (seconds - total + coolDown) ~/ coolDown;
    }
    return 152 + (8 * sin(seconds / 180)).round();
  }

  // Forty seconds of work, then ninety of rest.
  static int _setBpm(int seconds) =>
      seconds % 130 < 40 ? 126 + seconds % 130 ~/ 4 : 104;

  List<SyncRun> _syncRuns() => [
    for (final (index, minutesAgo) in const [120, 60, 0].indexed)
      SyncRun(
        at: now.subtract(Duration(minutes: minutesAgo)),
        outcome: SyncRunOutcome.completed,
        kinds: RecordKind.values.toSet(),
        recordCount: 30 + index * 4,
        battery: BatteryStatus(percent: 78 - index, charging: false),
        heartRateIntervalSeen: heartRateInterval,
      ),
  ];
}

@immutable
final class _WorkoutPlan {
  const new({
    required this.type,
    required this.daysAgo,
    required this.hour,
    required this.minute,
    required this.minutes,
  });

  final WorkoutType type;
  final int daysAgo;
  final int hour;
  final int minute;
  final int minutes;
}

@immutable
final class _Night {
  const new({
    required this.bed,
    required this.wake,
    required this.restingBpm,
    required this.hrvMs,
    required this.segments,
  });

  final DateTime bed;
  final DateTime wake;
  final int restingBpm;
  final int hrvMs;
  final List<SleepSegment> segments;

  bool covers(DateTime at) => !at.isBefore(bed) && at.isBefore(wake);

  SleepStage? stageAt(DateTime at) {
    for (final segment in segments) {
      if (!at.isBefore(segment.start) && at.isBefore(segment.end)) {
        return segment.stage;
      }
    }
    return null;
  }
}

@immutable
final class _Moment {
  const new({this.night, this.stage, this.workout});

  final _Night? night;
  final SleepStage? stage;
  final FinishedWorkout? workout;

  bool get asleep => night != null;
}

final class _Timeline {
  const new({required this.nights, required this.workouts});

  final Map<int, _Night> nights;
  final List<FinishedWorkout> workouts;

  _Moment at(DateTime at) {
    for (final workout in workouts) {
      if (!at.isBefore(workout.start) && at.isBefore(workout.end)) {
        return _Moment(workout: workout);
      }
    }
    final night = _nightAt(at);
    if (night == null) return const _Moment();
    return _Moment(night: night, stage: night.stageAt(at));
  }

  _Night? _nightAt(DateTime at) {
    final morning = nights[DemoDataGenerator._key(at)];
    if (morning != null && morning.covers(at)) return morning;
    final next = DateTime(at.year, at.month, at.day + 1);
    final evening = nights[DemoDataGenerator._key(next)];
    if (evening != null && evening.covers(at)) return evening;
    return null;
  }
}
