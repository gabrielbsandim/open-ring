import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/heart/domain/spot_reading_store.dart';
import 'package:open_ring/features/ring/infrastructure/ring_samples_dao.dart';
import 'package:open_ring/features/ring/infrastructure/write_summary.dart';
import 'package:ring_driver/ring_driver.dart';

final class DriftSpotReadingStore implements SpotReadingStore {
  new(this._db)
    : _samples = RingSamplesDao(_db),
      _outbox = HealthOutboxDao(_db);

  final AppDatabase _db;
  final RingSamplesDao _samples;
  final HealthOutboxDao _outbox;

  @override
  Future<void> save(String deviceId, LiveReading reading) =>
      _db.transaction(() async {
        final (kind, summary) = switch (reading.kind) {
          LiveKind.heartRate => (
            RecordKind.heartRate,
            await _samples.upsertHeartRate(deviceId, [
              HeartRateSample(at: reading.at, bpm: reading.value),
            ]),
          ),
          LiveKind.spo2 => (
            RecordKind.spo2,
            await _samples.upsertSpo2(deviceId, [
              Spo2Sample(at: reading.at, percent: reading.value),
            ]),
          ),
        };
        await _enqueue(kind, deviceId, summary, reading.at);
      });

  Future<void> _enqueue(
    RecordKind kind,
    String deviceId,
    WriteSummary summary,
    DateTime at,
  ) async {
    final (from, to) = (summary.from, summary.to);
    if (from == null || to == null) return;
    await _outbox.enqueue(
      kind: kind,
      deviceId: deviceId,
      from: from,
      to: to,
      recordCount: summary.count,
      at: at,
    );
  }
}
