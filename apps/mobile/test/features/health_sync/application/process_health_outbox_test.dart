import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/application/process_health_outbox.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';
import 'package:open_ring/features/health_sync/domain/health_write_preferences.dart';
import 'package:open_ring/features/health_sync/domain/retry_policy.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_health_record_source.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/ring/application/sync_ring.dart';
import 'package:open_ring/features/ring/domain/ring_sync_batch.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:open_ring/features/ring/infrastructure/sync_locks_dao.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';
import '../../../helpers/fake_health_writer.dart';
import '../../../helpers/fake_ring_driver.dart';
import '../../../helpers/sync_fixtures.dart';

void main() {
  late AppDatabase db;
  late FakeHealthWriter writer;
  late DateTime now;

  setUp(() async {
    db = await pairedDatabase();
    writer = FakeHealthWriter();
    now = syncNow;
  });

  ProcessHealthOutbox processor({
    RetryPolicy retry = const RetryPolicy(),
    HealthWritePreferences writes = const AllHealthWritesEnabled(),
  }) => ProcessHealthOutbox(
    writes: writes,
    outbox: HealthOutboxDao(db),
    source: DriftHealthRecordSource(db),
    writer: writer,
    lock: SyncLocksDao(db, name: SyncLocksDao.healthOutbox),
    clock: () => now,
    retry: retry,
  );

  Future<void> syncRing([FakeRingDriver? driver]) => SyncRing(
    driver: driver ?? loadedDriver(),
    store: DriftSyncStore(db),
    clock: () => now,
  )(ringId);

  Future<void> saveRevision({
    List<HeartRateSample>? heartRate,
    List<SleepSegment>? sleep,
  }) => DriftSyncStore(db).save(
    RingSyncBatch(
      deviceId: ringId,
      identity: ringIdentity,
      syncedAt: now,
      heartRate: heartRate,
      sleep: sleep,
    ),
  );

  Future<Map<HealthRecordKind, HealthOutboxRow>> rowsByKind() async => {
    for (final row in await HealthOutboxDao(db).all()) row.kind: row,
  };

  String id(HealthEntryType type, DateTime start) =>
      HealthRecordId.of(ringId, type, start);

  group('a disabled type', () {
    test('is never written and its rows end disabled, not done', () async {
      await syncRing();
      final writes = InMemoryHealthWritePreferences({
        HealthRecordKind.heartRate,
      });

      final report = await processor(writes: writes)();

      expect(
        writer.batches.map((b) => b.kind),
        isNot(contains(HealthRecordKind.heartRate)),
      );
      expect(writer.batches, isNotEmpty);
      expect(report.disabled, 1);
      final rows = await rowsByKind();
      expect(rows[HealthRecordKind.heartRate]!.status, OutboxStatus.disabled);
      expect(rows[HealthRecordKind.heartRate]!.lastError, isNull);
      expect(rows[HealthRecordKind.sleep]!.status, OutboxStatus.done);
    });

    test('rows queued after the toggle are held too', () async {
      final writes = InMemoryHealthWritePreferences({HealthRecordKind.sleep});
      await syncRing();
      await processor(writes: writes)();
      final before = writer.batches.length;
      now = now.add(const Duration(days: 1));
      await saveRevision(
        sleep: [
          SleepSegment(
            start: nightStart,
            end: nightStart.add(const Duration(hours: 1)),
            stage: SleepStage.light,
          ),
        ],
      );

      await processor(writes: writes)();

      expect(writer.batches, hasLength(before));
      expect(
        (await HealthOutboxDao(db).all())
            .where((r) => r.kind == HealthRecordKind.sleep)
            .map((r) => r.status),
        everyElement(OutboxStatus.disabled),
      );
    });

    test('is checked before access, so a denied type is still held', () async {
      await syncRing();
      writer.denied.add(HealthRecordKind.heartRate);

      await processor(
        writes: InMemoryHealthWritePreferences({HealthRecordKind.heartRate}),
      )();

      expect(
        (await rowsByKind())[HealthRecordKind.heartRate]!.status,
        OutboxStatus.disabled,
      );
    });

    test('restored rows are written on the next pass', () async {
      await syncRing();
      final writes = InMemoryHealthWritePreferences({
        HealthRecordKind.heartRate,
      });
      await processor(writes: writes)();
      await HealthOutboxDao(db).restoreDisabled(HealthRecordKind.heartRate);

      await processor()();

      expect(
        writer.batches.map((b) => b.kind),
        contains(HealthRecordKind.heartRate),
      );
      expect(
        (await rowsByKind())[HealthRecordKind.heartRate]!.status,
        OutboxStatus.done,
      );
    });
  });

  test('first send writes every ring kind once and skips stress', () async {
    await syncRing();

    final report = await processor()();

    expect(report.written, 5);
    expect(report.notApplicable, 1);
    expect(report.denied, isEmpty);
    final rows = await rowsByKind();
    expect(rows[HealthRecordKind.stress]?.status, OutboxStatus.notApplicable);
    for (final kind in [
      HealthRecordKind.activity,
      HealthRecordKind.heartRate,
      HealthRecordKind.spo2,
      HealthRecordKind.hrv,
      HealthRecordKind.sleep,
    ]) {
      expect(rows[kind]?.status, OutboxStatus.done, reason: '$kind');
      expect(rows[kind]?.completedAtUtcMs, syncNow.millisecondsSinceEpoch);
    }
    expect(writer.entriesOf(HealthRecordKind.activity), hasLength(4));
    expect(writer.entriesOf(HealthRecordKind.heartRate), hasLength(3));
    expect(writer.recordsOf(HealthRecordKind.heartRate), hasLength(2));
    expect(writer.entriesOf(HealthRecordKind.spo2), hasLength(1));
    expect(writer.entriesOf(HealthRecordKind.hrv), hasLength(1));
    final sleep = writer.entriesOf(HealthRecordKind.sleep).single as SleepEntry;
    expect(sleep.id, id(HealthEntryType.sleepSession, nightStart));
    expect(sleep.stages.map((s) => s.stage), contains(SleepStage.rem));
    expect(writer.inserted, hasLength(9));
    expect(writer.updated, isEmpty);
    expect(writer.platform.values.map((r) => r.version).toSet(), {
      syncNow.millisecondsSinceEpoch,
    });
  });

  test(
    'a re-send rebuilds the whole hour series with a higher version',
    () async {
      await syncRing();
      await processor()();
      writer.inserted.clear();
      now = syncNow.add(const Duration(hours: 1));
      final revisedAt = nightHeartRate[1].at;
      await saveRevision(heartRate: [HeartRateSample(at: revisedAt, bpm: 70)]);

      await processor()();

      final hourId = id(HealthEntryType.heartRateSeries, nightHeartRate[0].at);
      expect(writer.inserted, isEmpty);
      expect(writer.updated, [hourId]);
      expect(writer.recordsOf(HealthRecordKind.heartRate), hasLength(2));
      expect(writer.entriesOf(HealthRecordKind.heartRate), hasLength(3));
      final hour = writer.platform[hourId];
      final samples = (hour?.entry as HeartRateSeriesEntry?)?.samples;
      expect(samples?.map((s) => s.bpm), [64, 70]);
      expect(hour?.version, now.millisecondsSinceEpoch);
    },
  );

  test(
    'a denied kind stays pending untouched until access is granted',
    () async {
      await syncRing();
      writer.denied.add(HealthRecordKind.heartRate);

      final report = await processor()();

      expect(report.denied, {HealthRecordKind.heartRate});
      expect(report.written, 4);
      final pending = (await rowsByKind())[HealthRecordKind.heartRate];
      expect(pending?.status, OutboxStatus.pending);
      expect(pending?.attempts, 0);
      expect(pending?.lastError, isNull);
      expect(writer.entriesOf(HealthRecordKind.heartRate), isEmpty);

      writer.denied.clear();
      final retried = await processor()();

      expect(retried.written, 1);
      expect(retried.denied, isEmpty);
      expect(writer.entriesOf(HealthRecordKind.heartRate), hasLength(3));
    },
  );

  test(
    'a deferred kind waits without an attempt or a denial and sends later',
    () async {
      await syncRing();
      writer.deferred.add(HealthRecordKind.sleep);

      final report = await processor()();

      expect(report.denied, isEmpty);
      expect(report.retrying, 0);
      expect(report.written, 4);
      final waiting = (await rowsByKind())[HealthRecordKind.sleep];
      expect(waiting?.status, OutboxStatus.pending);
      expect(waiting?.attempts, 0);
      expect(waiting?.lastError, isNull);

      writer.deferred.clear();
      final later = await processor()();

      expect(later.written, 1);
      expect(writer.entriesOf(HealthRecordKind.sleep), isNotEmpty);
    },
  );

  test('an unavailable platform leaves every row pending', () async {
    await syncRing();
    writer.unavailable = true;

    final report = await processor()();

    expect(report.unavailable, isTrue);
    expect(report.written, 0);
    final rows = await HealthOutboxDao(db).pending();
    expect(rows.map((r) => r.attempts), everyElement(0));
    expect(rows, hasLength(6));
  });

  test('a transient error backs off, then the retry succeeds', () async {
    await syncRing();
    writer.failuresLeft = 1;

    final report = await processor()();

    expect(report.retrying, 1);
    final failed = (await rowsByKind())[HealthRecordKind.activity];
    expect(failed?.status, OutboxStatus.pending);
    expect(failed?.attempts, 1);
    expect(failed?.lastError, contains('platform busy'));
    expect(failed?.lastAttemptAtUtcMs, syncNow.millisecondsSinceEpoch);
    expect(
      failed?.nextAttemptAtUtcMs,
      syncNow.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
    );

    final early = await processor()();
    expect(early.written, 0);

    now = syncNow.add(const Duration(minutes: 1));
    final later = await processor()();

    expect(later.written, 1);
    final done = (await rowsByKind())[HealthRecordKind.activity];
    expect(done?.status, OutboxStatus.done);
    expect(writer.entriesOf(HealthRecordKind.activity), hasLength(4));
  });

  test(
    'gives up after the last attempt and never retries a dead row',
    () async {
      await syncRing(FakeRingDriver()..heartRate = [...nightHeartRate]);
      writer.failuresLeft = 100;
      const retry = RetryPolicy(maxAttempts: 3);

      final reports = <HealthOutboxReport>[];
      for (var run = 0; run < 4; run++) {
        reports.add(await processor(retry: retry)());
        now = now.add(const Duration(hours: 1));
      }

      expect(reports.map((r) => r.dead), [0, 0, 1, 0]);
      final row = (await rowsByKind())[HealthRecordKind.heartRate];
      expect(row?.status, OutboxStatus.dead);
      expect(row?.attempts, 3);
      expect(row?.nextAttemptAtUtcMs, isNull);
      expect(writer.failuresLeft, 100 - 3);
    },
  );

  test('a night whose start moved replaces the old session', () async {
    await syncRing();
    await processor()();
    final movedStart = DateTime(2026, 11, 9, 22, 30);
    now = syncNow.add(const Duration(hours: 2));
    await saveRevision(
      sleep: [
        SleepSegment(
          start: movedStart,
          end: lastNight.first.end,
          stage: SleepStage.light,
        ),
        ...lastNight.skip(1),
      ],
    );

    await processor()();

    final sleep = writer.entriesOf(HealthRecordKind.sleep);
    expect(sleep.map((e) => e.id), [
      id(HealthEntryType.sleepSession, movedStart),
    ]);
    expect(
      writer.platform.containsKey(id(HealthEntryType.sleepSession, nightStart)),
      isFalse,
    );
    final stages = (sleep.single as SleepEntry).stages;
    expect(stages.first.id, id(HealthEntryType.sleepStage, movedStart));
    expect(stages.map((s) => s.stage), contains(SleepStage.rem));
    final batch = writer.batches.last;
    expect(batch.from.isAfter(movedStart), isFalse);
    expect(batch.to.isAfter(lastNight.last.end), isTrue);
  });

  test(
    'runs while the ring sync holds its lock, but alone per outbox',
    () async {
      await syncRing();
      await SyncLocksDao(db)
          .acquire('ring', at: now, timeout: const Duration(minutes: 10));

      final report = await processor()();
      expect(report.written, 5);

      await HealthOutboxDao(db)
          .enqueueWorkout(start: nightStart, end: syncNow, at: syncNow);
      await SyncLocksDao(
        db,
        name: SyncLocksDao.healthOutbox,
      ).acquire('other', at: now, timeout: const Duration(minutes: 10));
      final busy = await processor()();

      expect(busy.busy, isTrue);
      expect(
        (await rowsByKind())[HealthRecordKind.workout]?.status,
        OutboxStatus.pending,
      );
    },
  );

  test(
    'a workout carries its HR series and route, and owns HR in its window',
    () async {
      final start = DateTime(2026, 11, 9, 21, 58);
      final end = DateTime(2026, 11, 9, 22, 10);
      final workoutId = await db
          .into(db.workouts)
          .insert(
            WorkoutsCompanion.insert(
              clientId: 'w1',
              activityType: 'running',
              startUtcMs: start.millisecondsSinceEpoch,
              endUtcMs: Value(end.millisecondsSinceEpoch),
              offsetMinutes: 60,
              distanceMeters: const Value(2100),
              activeKilocalories: const Value(150),
            ),
          );
      final hrAt = DateTime(2026, 11, 9, 22, 1);
      await db
          .into(db.workoutHrSamples)
          .insert(
            WorkoutHrSamplesCompanion.insert(
              workoutId: workoutId,
              atUtcMs: hrAt.millisecondsSinceEpoch,
              offsetMinutes: 60,
              bpm: 142,
            ),
          );
      await db
          .into(db.workoutRoutePoints)
          .insert(
            WorkoutRoutePointsCompanion.insert(
              workoutId: workoutId,
              atUtcMs: hrAt.millisecondsSinceEpoch,
              offsetMinutes: 60,
              latitude: -23.55,
              longitude: -46.63,
            ),
          );
      await HealthOutboxDao(db).enqueueWorkout(start: start, end: end, at: now);
      await syncRing(FakeRingDriver()..heartRate = [...nightHeartRate]);

      await processor()();

      final workout =
          writer.entriesOf(HealthRecordKind.workout).single as WorkoutEntry;
      expect(
        workout.id,
        HealthRecordId.of('phone', HealthEntryType.workout, start),
      );
      expect(workout.heartRate.map((s) => s.bpm), [142]);
      expect(workout.route.single.latitude, -23.55);
      expect(writer.entriesOf(HealthRecordKind.heartRate).map((e) => e.start), [
        nightHeartRate.last.at,
      ]);
      final hrBatches = [
        for (final batch in writer.batches)
          if (batch.kind == HealthRecordKind.heartRate) batch,
      ];
      for (final batch in hrBatches) {
        final overlaps = batch.from.isBefore(end) && batch.to.isAfter(start);
        expect(overlaps, isFalse, reason: '${batch.from} to ${batch.to}');
      }
    },
  );
}
