import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_status.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_outbox_summary_reader.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';

import '../../../helpers/database.dart';

void main() {
  final from = DateTime.utc(2026, 11, 9);
  final to = DateTime.utc(2026, 11, 10);

  test('an empty outbox has nothing pending and nothing sent', () async {
    final summary = await DriftOutboxSummaryReader(memoryDatabase()).summary();

    expect(summary.pendingRecordCount, 0);
    expect(summary.pendingRows, 0);
    expect(summary.deadRows, 0);
    expect(summary.lastDeadError, isNull);
    expect(summary.oldestPendingAt, isNull);
    expect(summary.lastSentAt, isNull);
  });

  test(
    'counts pending records per kind, dead rows and the last send',
    () async {
      final db = memoryDatabase();
      final outbox = HealthOutboxDao(db);
      Future<int> enqueue(RecordKind kind, int count, int hour) =>
          outbox.enqueue(
            kind: kind,
            deviceId: ringId,
            from: from,
            to: to,
            recordCount: count,
            at: DateTime.utc(2026, 11, 10, hour),
          );

      await enqueue(RecordKind.heartRate, 200, 6);
      await enqueue(RecordKind.heartRate, 41, 7);
      await enqueue(RecordKind.sleep, 2, 8);
      await enqueue(RecordKind.stress, 90, 5);
      final done = await enqueue(RecordKind.spo2, 18, 4);
      await outbox.markDone(done, at: DateTime.utc(2026, 11, 10, 4, 30));
      final dead = await enqueue(RecordKind.hrv, 12, 3);
      await outbox.markDead(
        dead,
        error: 'busy',
        at: DateTime.utc(2026, 11, 10, 3),
      );
      await outbox.enqueueWorkout(
        start: from,
        end: from.add(const Duration(hours: 1)),
        at: DateTime.utc(2026, 11, 10, 9),
      );

      final summary = await DriftOutboxSummaryReader(db).summary();

      expect(summary.pendingRecords, {
        HealthRecordKind.heartRate: 241,
        HealthRecordKind.sleep: 2,
        HealthRecordKind.workout: 1,
      });
      expect(summary.pendingRecordCount, 244);
      expect(summary.pendingRows, 4);
      expect(summary.deadRows, 1);
      expect(summary.lastDeadError, 'busy');
      expect(summary.oldestPendingAt?.toUtc(), DateTime.utc(2026, 11, 10, 6));
      expect(summary.lastSentAt?.toUtc(), DateTime.utc(2026, 11, 10, 4, 30));
    },
  );

  test('the dead error shown is the one from the latest attempt', () async {
    final db = memoryDatabase();
    final outbox = HealthOutboxDao(db);
    Future<int> enqueue(RecordKind kind) => outbox.enqueue(
      kind: kind,
      deviceId: ringId,
      from: from,
      to: to,
      recordCount: 1,
      at: to,
    );
    final older = await enqueue(RecordKind.spo2);
    final newer = await enqueue(RecordKind.heartRate);
    await outbox.markDead(
      newer,
      error: 'SecurityException: denied',
      at: DateTime.utc(2026, 11, 10, 7),
    );
    await outbox.markDead(
      older,
      error: 'HealthWriteException: write SPO2 failed',
      at: DateTime.utc(2026, 11, 10, 6),
    );

    final summary = await DriftOutboxSummaryReader(db).summary();

    expect(summary.deadRows, 2);
    expect(summary.lastDeadError, 'SecurityException: denied');
    expect(summary.deadCause, OutboxFailure.permission);
  });

  test('held rows are counted apart and are not waiting to send', () async {
    final db = memoryDatabase();
    final outbox = HealthOutboxDao(db);
    final held = await outbox.enqueue(
      kind: RecordKind.heartRate,
      deviceId: ringId,
      from: from,
      to: to,
      recordCount: 200,
      at: to,
    );
    await outbox.markDisabled(held, at: to);
    await outbox.enqueue(
      kind: RecordKind.sleep,
      deviceId: ringId,
      from: from,
      to: to,
      recordCount: 2,
      at: to,
    );

    final summary = await DriftOutboxSummaryReader(db).summary();

    expect(summary.disabledRecords, {HealthRecordKind.heartRate: 200});
    expect(summary.pendingRecords, {HealthRecordKind.sleep: 2});
    expect(summary.pendingRows, 1);
    expect(summary.lastSentAt, isNull);
  });
}
