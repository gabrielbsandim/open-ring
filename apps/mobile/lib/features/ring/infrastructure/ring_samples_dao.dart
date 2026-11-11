import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/database/tables/sample_tables.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/ring/infrastructure/write_summary.dart';
import 'package:ring_driver/ring_driver.dart';

part 'ring_samples_dao.g.dart';

@DriftAccessor(
  tables: [ActivityBuckets, HrSamples, Spo2Samples, StressSamples, HrvSamples],
)
class RingSamplesDao extends DatabaseAccessor<AppDatabase>
    with _$RingSamplesDaoMixin {
  new(super.attachedDatabase);

  Future<WriteSummary> upsertActivity(
    String deviceId,
    List<ActivityBucket> buckets,
  ) => writeEach(
    buckets,
    start: (bucket) => bucket.start,
    end: (bucket) => bucket.start.add(bucket.duration),
    write: (bucket) => into(activityBuckets).insertReturningOrNull(
      ActivityBucketsCompanion.insert(
        deviceId: deviceId,
        startUtcMs: bucket.start.utcMs,
        offsetMinutes: bucket.start.offsetMinutes,
        durationSeconds: bucket.duration.inSeconds,
        steps: bucket.steps,
        distanceMeters: bucket.distanceMeters,
        activeKilocalories: bucket.activeKilocalories,
      ),
      onConflict: DoUpdate.withExcluded(
        (old, excluded) => ActivityBucketsCompanion.custom(
          offsetMinutes: excluded.offsetMinutes,
          durationSeconds: excluded.durationSeconds,
          steps: excluded.steps,
          distanceMeters: excluded.distanceMeters,
          activeKilocalories: excluded.activeKilocalories,
        ),
        where: (old, excluded) =>
            old.offsetMinutes.isNotExp(excluded.offsetMinutes) |
            old.durationSeconds.isNotExp(excluded.durationSeconds) |
            old.steps.isNotExp(excluded.steps) |
            old.distanceMeters.isNotExp(excluded.distanceMeters) |
            old.activeKilocalories.isNotExp(excluded.activeKilocalories),
      ),
    ),
  );

  Future<WriteSummary> upsertHeartRate(
    String deviceId,
    List<HeartRateSample> samples,
  ) => _writeAt(
    samples,
    (sample) => sample.at,
    (sample) => into(hrSamples).insertReturningOrNull(
      HrSamplesCompanion.insert(
        deviceId: deviceId,
        atUtcMs: sample.at.utcMs,
        offsetMinutes: sample.at.offsetMinutes,
        bpm: sample.bpm,
      ),
      onConflict: DoUpdate.withExcluded(
        (old, excluded) => HrSamplesCompanion.custom(
          offsetMinutes: excluded.offsetMinutes,
          bpm: excluded.bpm,
        ),
        where: (old, excluded) =>
            old.offsetMinutes.isNotExp(excluded.offsetMinutes) |
            old.bpm.isNotExp(excluded.bpm),
      ),
    ),
  );

  Future<WriteSummary> upsertSpo2(String deviceId, List<Spo2Sample> samples) =>
      _writeAt(
        samples,
        (sample) => sample.at,
        (sample) => into(spo2Samples).insertReturningOrNull(
          Spo2SamplesCompanion.insert(
            deviceId: deviceId,
            atUtcMs: sample.at.utcMs,
            offsetMinutes: sample.at.offsetMinutes,
            percent: sample.percent,
          ),
          onConflict: DoUpdate.withExcluded(
            (old, excluded) => Spo2SamplesCompanion.custom(
              offsetMinutes: excluded.offsetMinutes,
              percent: excluded.percent,
            ),
            where: (old, excluded) =>
                old.offsetMinutes.isNotExp(excluded.offsetMinutes) |
                old.percent.isNotExp(excluded.percent),
          ),
        ),
      );

  Future<WriteSummary> upsertStress(
    String deviceId,
    List<StressSample> samples,
  ) => _writeAt(
    samples,
    (sample) => sample.at,
    (sample) => into(stressSamples).insertReturningOrNull(
      StressSamplesCompanion.insert(
        deviceId: deviceId,
        atUtcMs: sample.at.utcMs,
        offsetMinutes: sample.at.offsetMinutes,
        level: sample.level,
      ),
      onConflict: DoUpdate.withExcluded(
        (old, excluded) => StressSamplesCompanion.custom(
          offsetMinutes: excluded.offsetMinutes,
          level: excluded.level,
        ),
        where: (old, excluded) =>
            old.offsetMinutes.isNotExp(excluded.offsetMinutes) |
            old.level.isNotExp(excluded.level),
      ),
    ),
  );

  Future<WriteSummary> upsertHrv(String deviceId, List<HrvSample> samples) =>
      _writeAt(
        samples,
        (sample) => sample.at,
        (sample) => into(hrvSamples).insertReturningOrNull(
          HrvSamplesCompanion.insert(
            deviceId: deviceId,
            atUtcMs: sample.at.utcMs,
            offsetMinutes: sample.at.offsetMinutes,
            milliseconds: sample.milliseconds,
          ),
          onConflict: DoUpdate.withExcluded(
            (old, excluded) => HrvSamplesCompanion.custom(
              offsetMinutes: excluded.offsetMinutes,
              milliseconds: excluded.milliseconds,
            ),
            where: (old, excluded) =>
                old.offsetMinutes.isNotExp(excluded.offsetMinutes) |
                old.milliseconds.isNotExp(excluded.milliseconds),
          ),
        ),
      );

  static Future<WriteSummary> _writeAt<T>(
    List<T> samples,
    DateTime Function(T sample) at,
    Future<Object?> Function(T sample) write,
  ) => writeEach(samples, start: at, end: at, write: write);
}
