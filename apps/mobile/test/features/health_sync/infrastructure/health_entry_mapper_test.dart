import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';
import 'package:open_ring/features/health_sync/domain/health_outbox_store.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_health_record_source.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_entry_mapper.dart';
import 'package:open_ring/features/ring/domain/ring_sync_batch.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';
import '../../../helpers/sync_fixtures.dart';

final start = DateTime(2026, 11, 9, 22);
final int ms = start.millisecondsSinceEpoch;

String id(HealthEntryType type, DateTime at, [String device = ringId]) =>
    HealthRecordId.of(device, type, at);

void main() {
  test('a client record id is stable for device, type and start', () {
    expect(
      HealthRecordId.of(ringId, HealthEntryType.heartRate, start),
      'openring:$ringId:heartRate:$ms',
    );
  });

  group('activity', () {
    ActivityBucketRow bucket({int steps = 420, double kcal = 18.5}) =>
        ActivityBucketRow(
          deviceId: ringId,
          startUtcMs: ms,
          offsetMinutes: 60,
          durationSeconds: 900,
          steps: steps,
          distanceMeters: 310,
          activeKilocalories: kcal,
        );

    test('one bucket becomes steps and active energy over its span', () {
      final end = start.add(const Duration(minutes: 15));

      expect(activityEntries(bucket()), [
        StepsEntry(
          id: id(HealthEntryType.steps, start),
          start: start,
          end: end,
          count: 420,
        ),
        ActiveEnergyEntry(
          id: id(HealthEntryType.activeEnergy, start),
          start: start,
          end: end,
          kilocalories: 18.5,
        ),
      ]);
    });

    test('an empty bucket writes nothing', () {
      expect(activityEntries(bucket(steps: 0, kcal: 0)), isEmpty);
    });
  });

  group('samples', () {
    HrSampleRow hr(int bpm) =>
        HrSampleRow(deviceId: ringId, atUtcMs: ms, offsetMinutes: 60, bpm: bpm);

    test('heart rate maps one sample and drops out of range readings', () {
      expect(
        heartRateEntry(hr(64)),
        HeartRateEntry(
          id: id(HealthEntryType.heartRate, start),
          at: start,
          bpm: 64,
        ),
      );
      expect(heartRateEntry(hr(0)), isNull);
      expect(heartRateEntry(hr(301)), isNull);
    });

    test('SpO2 keeps the percent and drops a zero reading', () {
      Spo2SampleRow row(int percent) => Spo2SampleRow(
        deviceId: ringId,
        atUtcMs: ms,
        offsetMinutes: 60,
        percent: percent,
      );

      expect(
        spo2Entry(row(97)),
        Spo2Entry(id: id(HealthEntryType.spo2, start), at: start, percent: 97),
      );
      expect(spo2Entry(row(0)), isNull);
    });

    test('HRV keeps milliseconds within the Health Connect range', () {
      HrvSampleRow row(int value) => HrvSampleRow(
        deviceId: ringId,
        atUtcMs: ms,
        offsetMinutes: 60,
        milliseconds: value,
      );

      expect(
        hrvEntry(row(55)),
        HrvEntry(
          id: id(HealthEntryType.hrv, start),
          at: start,
          milliseconds: 55,
        ),
      );
      expect(hrvEntry(row(0)), isNull);
      expect(hrvEntry(row(201)), isNull);
    });
  });

  test('a sleep session carries its stages in order, REM included', () {
    final session = SleepSessionRow(
      deviceId: ringId,
      startUtcMs: nightStart.millisecondsSinceEpoch,
      endUtcMs: lastNight.last.end.millisecondsSinceEpoch,
      offsetMinutes: 60,
    );
    final segments = [
      for (final segment in lastNight.reversed)
        SleepSegmentRow(
          deviceId: ringId,
          startUtcMs: segment.start.millisecondsSinceEpoch,
          endUtcMs: segment.end.millisecondsSinceEpoch,
          offsetMinutes: 60,
          stage: segment.stage,
          sessionStartUtcMs: session.startUtcMs,
        ),
    ];

    final entry = sleepEntry(session, segments);

    expect(entry.id, id(HealthEntryType.sleepSession, nightStart));
    expect((entry.start, entry.end), (nightStart, lastNight.last.end));
    expect(entry.stages, [
      for (final segment in lastNight)
        SleepStageEntry(
          id: id(HealthEntryType.sleepStage, segment.start),
          start: segment.start,
          end: segment.end,
          stage: segment.stage,
        ),
    ]);
    expect(entry.stages.map((s) => s.stage), contains(SleepStage.rem));
  });

  group('workout', () {
    final end = start.add(const Duration(minutes: 30));
    WorkoutRow workout({int? endUtcMs, double? distance = 5000}) => WorkoutRow(
      id: 1,
      clientId: 'w1',
      activityType: 'running',
      startUtcMs: ms,
      endUtcMs: endUtcMs,
      offsetMinutes: 60,
      distanceMeters: distance,
      activeKilocalories: 0,
    );
    WorkoutHrSampleRow hr(DateTime at, int bpm) => WorkoutHrSampleRow(
      workoutId: 1,
      atUtcMs: at.millisecondsSinceEpoch,
      offsetMinutes: 60,
      bpm: bpm,
    );
    WorkoutRoutePointRow point(DateTime at) => WorkoutRoutePointRow(
      workoutId: 1,
      atUtcMs: at.millisecondsSinceEpoch,
      offsetMinutes: 60,
      latitude: 1,
      longitude: 2,
      altitudeMeters: 3,
      accuracyMeters: 4,
    );

    test('keeps HR and route inside the session and drops empty totals', () {
      final inside = start.add(const Duration(minutes: 5));
      final after = end.add(const Duration(minutes: 1));

      final entry = workoutEntry(
        workout(endUtcMs: end.millisecondsSinceEpoch),
        [hr(inside, 150), hr(after, 120), hr(inside, 0)],
        [point(inside), point(after)],
      );

      expect(
        entry,
        WorkoutEntry(
          id: id(HealthEntryType.workout, start, HealthRecordId.phone),
          start: start,
          end: end,
          activityType: 'running',
          distanceMeters: 5000,
          heartRateSeries: [
            HeartRateSeriesEntry(
              id: id(
                HealthEntryType.workoutHeartRateSeries,
                start,
                HealthRecordId.phone,
              ),
              start: start,
              end: end,
              samples: [
                HeartRateEntry(
                  id: id(
                    HealthEntryType.workoutHeartRate,
                    inside,
                    HealthRecordId.phone,
                  ),
                  at: inside,
                  bpm: 150,
                ),
              ],
            ),
          ],
          route: [
            RoutePoint(
              at: inside,
              latitude: 1,
              longitude: 2,
              altitudeMeters: 3,
              accuracyMeters: 4,
            ),
          ],
        ),
      );
    });

    test('an unfinished workout is not written', () {
      expect(workoutEntry(workout(), const [], const []), isNull);
    });
  });

  group('DriftHealthRecordSource', () {
    test('loads the sleep night of an outbox row as one batch', () async {
      final db = await pairedDatabase();
      await DriftSyncStore(db).save(
        RingSyncBatch(
          deviceId: ringId,
          identity: ringIdentity,
          syncedAt: syncNow,
          sleep: lastNight,
          stress: [StressSample(at: nightStart, level: 30)],
        ),
      );
      OutboxEntry entry(HealthRecordKind kind) => OutboxEntry(
        id: 1,
        kind: kind,
        deviceId: ringId,
        from: nightStart,
        to: lastNight.last.end,
        enqueuedAt: syncNow,
      );
      final source = DriftHealthRecordSource(db);

      final sleep = await source.batches(
        entry(HealthRecordKind.sleep),
        batchSize: 50,
      );
      final stress = await source.batches(
        entry(HealthRecordKind.stress),
        batchSize: 50,
      );

      final night = sleep.single.entries.single as SleepEntry;
      expect(night.stages, hasLength(lastNight.length));
      expect(sleep.single.version, syncNow.millisecondsSinceEpoch);
      expect(stress, isEmpty);
    });

    test('ring HR inside a workout with its own series is left out', () async {
      final db = await pairedDatabase();
      await DriftSyncStore(db).save(
        RingSyncBatch(
          deviceId: ringId,
          identity: ringIdentity,
          syncedAt: syncNow,
          heartRate: nightHeartRate,
        ),
      );
      final workoutId = await db
          .into(db.workouts)
          .insert(
            WorkoutsCompanion.insert(
              clientId: 'w1',
              activityType: 'walking',
              startUtcMs: start.millisecondsSinceEpoch,
              endUtcMs: Value(
                start.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
              ),
              offsetMinutes: 60,
            ),
          );
      await db
          .into(db.workoutHrSamples)
          .insert(
            WorkoutHrSamplesCompanion.insert(
              workoutId: workoutId,
              atUtcMs: start.millisecondsSinceEpoch,
              offsetMinutes: 60,
              bpm: 110,
            ),
          );

      final batches = await DriftHealthRecordSource(db).batches(
        OutboxEntry(
          id: 1,
          kind: HealthRecordKind.heartRate,
          deviceId: ringId,
          from: nightHeartRate.first.at,
          to: nightHeartRate.last.at,
          enqueuedAt: syncNow,
        ),
        batchSize: 50,
      );

      expect(batches.expand((b) => b.entries).map((e) => e.start), [
        nightHeartRate.last.at,
      ]);
    });

    test('ring HR goes out as one series per UTC hour, whole hours', () async {
      final db = await pairedDatabase();
      final hour = DateTime.utc(2026, 11, 9, 21).toLocal();
      DateTime minute(int m) => hour.add(Duration(minutes: m));
      await DriftSyncStore(db).save(
        RingSyncBatch(
          deviceId: ringId,
          identity: ringIdentity,
          syncedAt: syncNow,
          heartRate: [
            for (final m in [0, 5, 55, 60, 65])
              HeartRateSample(at: minute(m), bpm: 60 + m),
          ],
        ),
      );

      final batches = await DriftHealthRecordSource(db).batches(
        OutboxEntry(
          id: 1,
          kind: HealthRecordKind.heartRate,
          deviceId: ringId,
          from: minute(55),
          to: minute(60),
          enqueuedAt: syncNow,
        ),
        batchSize: 50,
      );

      final batch = batches.single;
      expect(batch.from, hour);
      expect(batch.to, minute(120));
      final series = batch.entries.cast<HeartRateSeriesEntry>();
      expect(series.map((s) => s.id), [
        id(HealthEntryType.heartRateSeries, minute(0)),
        id(HealthEntryType.heartRateSeries, minute(60)),
      ]);
      expect(series.map((s) => (s.start, s.end)), [
        (minute(0), minute(55)),
        (minute(60), minute(65)),
      ]);
      expect(series.map((s) => s.samples.map((x) => x.bpm)), [
        [60, 65, 115],
        [120, 125],
      ]);
    });
  });
}
