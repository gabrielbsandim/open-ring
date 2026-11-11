import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';
import 'package:open_ring/features/health_sync/domain/heart_rate_series.dart';

// Health Connect rejects a whole insert when one value is out of its range,
// so a ring reading outside it (0 means no reading) is never sent.
const ({int min, int max}) heartRateRange = (min: 1, max: 300);
const ({int min, int max}) spo2Range = (min: 1, max: 100);
const ({int min, int max}) hrvRange = (min: 1, max: 200);

bool _within(int value, ({int min, int max}) range) =>
    value >= range.min && value <= range.max;

List<HealthEntry> activityEntries(ActivityBucketRow row) {
  final start = fromUtcMs(row.startUtcMs);
  final end = start.add(Duration(seconds: row.durationSeconds));
  return [
    if (row.steps > 0)
      StepsEntry(
        id: HealthRecordId.of(row.deviceId, HealthEntryType.steps, start),
        start: start,
        end: end,
        count: row.steps,
      ),
    if (row.activeKilocalories > 0)
      ActiveEnergyEntry(
        id: HealthRecordId.of(
          row.deviceId,
          HealthEntryType.activeEnergy,
          start,
        ),
        start: start,
        end: end,
        kilocalories: row.activeKilocalories,
      ),
  ];
}

HeartRateEntry? heartRateEntry(HrSampleRow row) {
  if (!_within(row.bpm, heartRateRange)) return null;
  final at = fromUtcMs(row.atUtcMs);
  return HeartRateEntry(
    id: HealthRecordId.of(row.deviceId, HealthEntryType.heartRate, at),
    at: at,
    bpm: row.bpm,
  );
}

Spo2Entry? spo2Entry(Spo2SampleRow row) {
  if (!_within(row.percent, spo2Range)) return null;
  final at = fromUtcMs(row.atUtcMs);
  return Spo2Entry(
    id: HealthRecordId.of(row.deviceId, HealthEntryType.spo2, at),
    at: at,
    percent: row.percent,
  );
}

HrvEntry? hrvEntry(HrvSampleRow row) {
  if (!_within(row.milliseconds, hrvRange)) return null;
  final at = fromUtcMs(row.atUtcMs);
  return HrvEntry(
    id: HealthRecordId.of(row.deviceId, HealthEntryType.hrv, at),
    at: at,
    milliseconds: row.milliseconds,
  );
}

SleepEntry sleepEntry(SleepSessionRow session, List<SleepSegmentRow> segments) {
  final start = fromUtcMs(session.startUtcMs);
  final ordered = [...segments]
    ..sort((a, b) => a.startUtcMs.compareTo(b.startUtcMs));
  return SleepEntry(
    id: HealthRecordId.of(
      session.deviceId,
      HealthEntryType.sleepSession,
      start,
    ),
    start: start,
    end: fromUtcMs(session.endUtcMs),
    stages: [
      for (final segment in ordered)
        SleepStageEntry(
          id: HealthRecordId.of(
            segment.deviceId,
            HealthEntryType.sleepStage,
            fromUtcMs(segment.startUtcMs),
          ),
          start: fromUtcMs(segment.startUtcMs),
          end: fromUtcMs(segment.endUtcMs),
          stage: segment.stage,
        ),
    ],
  );
}

WorkoutEntry? workoutEntry(
  WorkoutRow workout,
  List<WorkoutHrSampleRow> heartRate,
  List<WorkoutRoutePointRow> route,
) {
  final endUtcMs = workout.endUtcMs;
  if (endUtcMs == null || endUtcMs <= workout.startUtcMs) return null;
  final device = workout.deviceId ?? HealthRecordId.phone;
  bool inside(int atUtcMs) =>
      atUtcMs >= workout.startUtcMs && atUtcMs <= endUtcMs;
  final start = fromUtcMs(workout.startUtcMs);
  final end = fromUtcMs(endUtcMs);
  return WorkoutEntry(
    id: HealthRecordId.of(device, HealthEntryType.workout, start),
    start: start,
    end: end,
    activityType: workout.activityType,
    distanceMeters: _positive(workout.distanceMeters),
    activeKilocalories: _positive(workout.activeKilocalories),
    heartRateSeries: workoutHeartRateSeries(
      device,
      start: start,
      end: end,
      samples: [
        for (final sample in heartRate)
          if (inside(sample.atUtcMs) && _within(sample.bpm, heartRateRange))
            HeartRateEntry(
              id: HealthRecordId.of(
                device,
                HealthEntryType.workoutHeartRate,
                fromUtcMs(sample.atUtcMs),
              ),
              at: fromUtcMs(sample.atUtcMs),
              bpm: sample.bpm,
            ),
      ],
    ),
    route: [
      for (final point in route)
        if (inside(point.atUtcMs))
          RoutePoint(
            at: fromUtcMs(point.atUtcMs),
            latitude: point.latitude,
            longitude: point.longitude,
            altitudeMeters: point.altitudeMeters,
            accuracyMeters: point.accuracyMeters,
          ),
    ],
  );
}

double? _positive(double? value) => value != null && value > 0 ? value : null;
