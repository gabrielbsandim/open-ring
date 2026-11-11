import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';

import '../../../helpers/database.dart';
import '../../../helpers/sync_fixtures.dart';

void main() {
  test('enqueued entries are pending in order with no attempts', () async {
    final dao = HealthOutboxDao(memoryDatabase());
    for (final kind in [RecordKind.sleep, RecordKind.heartRate]) {
      await dao.enqueue(
        kind: kind,
        deviceId: ringId,
        from: nightStart,
        to: syncNow,
        recordCount: 4,
        at: syncNow,
      );
    }

    final pending = await dao.pending();

    expect(pending.map((e) => e.kind), [
      HealthRecordKind.sleep,
      HealthRecordKind.heartRate,
    ]);
    expect(pending.first.fromUtcMs, nightStart.millisecondsSinceEpoch);
    expect(pending.first.toUtcMs, syncNow.millisecondsSinceEpoch);
    expect(pending.first.recordCount, 4);
    expect(pending.first.attempts, 0);
    expect(pending.first.completedAtUtcMs, isNull);
  });

  test('due skips rows waiting out a backoff and finished rows', () async {
    final dao = HealthOutboxDao(memoryDatabase());
    Future<int> add() => dao.enqueue(
      kind: RecordKind.heartRate,
      deviceId: ringId,
      from: nightStart,
      to: syncNow,
      recordCount: 1,
      at: syncNow,
    );
    final waiting = await add();
    final done = await add();
    final dead = await add();
    final ready = await add();
    final later = syncNow.add(const Duration(minutes: 5));
    await dao.markFailed(
      waiting,
      error: 'busy',
      at: syncNow,
      nextAttemptAt: later,
    );
    await dao.markDone(done, at: syncNow);
    await dao.markDead(dead, error: 'gone', at: syncNow);

    expect((await dao.due(syncNow)).map((e) => e.id), [ready]);
    expect((await dao.due(later)).map((e) => e.id), [waiting, ready]);
    final rows = {for (final row in await dao.all()) row.id: row};
    expect(rows[waiting]?.attempts, 1);
    expect(rows[waiting]?.lastError, 'busy');
    expect(rows[dead]?.status, OutboxStatus.dead);
    expect(rows[dead]?.attempts, 1);
    expect(rows[done]?.status, OutboxStatus.done);
  });

  test('a workout row spans the session and has no ring device', () async {
    final dao = HealthOutboxDao(memoryDatabase());

    await dao.enqueueWorkout(start: nightStart, end: syncNow, at: syncNow);

    final entry = (await dao.due(syncNow)).single;
    expect(entry.kind, HealthRecordKind.workout);
    expect(entry.deviceId, isNull);
    expect((entry.from, entry.to), (nightStart, syncNow));
    expect(entry.version, syncNow.millisecondsSinceEpoch);
  });

  group('dead rows', () {
    late HealthOutboxDao dao;
    late int heartDead;
    late int heartDeadLater;
    late int sleepDead;
    late int pending;
    late int done;

    setUp(() async {
      dao = HealthOutboxDao(memoryDatabase());
      Future<int> add(RecordKind kind) => dao.enqueue(
        kind: kind,
        deviceId: ringId,
        from: nightStart,
        to: syncNow,
        recordCount: 3,
        at: syncNow,
      );
      heartDead = await add(RecordKind.heartRate);
      heartDeadLater = await add(RecordKind.heartRate);
      sleepDead = await add(RecordKind.sleep);
      pending = await add(RecordKind.heartRate);
      done = await add(RecordKind.sleep);
      for (var attempt = 0; attempt < 7; attempt++) {
        await dao.markFailed(
          heartDead,
          error: 'busy',
          at: syncNow,
          nextAttemptAt: syncNow,
        );
      }
      await dao.markDead(heartDead, error: 'busy', at: syncNow);
      await dao.markDead(
        heartDeadLater,
        error: 'SecurityException: no permission',
        at: syncNow.add(const Duration(minutes: 1)),
      );
      await dao.markDead(sleepDead, error: 'gone', at: syncNow);
      await dao.markFailed(
        pending,
        error: 'busy',
        at: syncNow,
        nextAttemptAt: syncNow.add(const Duration(hours: 1)),
      );
      await dao.markDone(done, at: syncNow);
    });

    test('report the latest error per kind', () async {
      expect(await dao.lastDeadErrors(), {
        HealthRecordKind.heartRate: 'SecurityException: no permission',
        HealthRecordKind.sleep: 'gone',
      });
    });

    test('reset to pending with a fresh budget and no error', () async {
      final reset = await dao.resetDead();

      expect(reset, 3);
      final rows = {for (final row in await dao.all()) row.id: row};
      for (final id in [heartDead, heartDeadLater, sleepDead]) {
        expect(rows[id]?.status, OutboxStatus.pending);
        expect(rows[id]?.attempts, 0);
        expect(rows[id]?.lastError, isNull);
        expect(rows[id]?.nextAttemptAtUtcMs, isNull);
      }
      expect(rows[pending]?.attempts, 1);
      expect(rows[pending]?.lastError, 'busy');
      expect(rows[done]?.status, OutboxStatus.done);
      expect((await dao.due(syncNow)).map((e) => e.id), [
        heartDead,
        heartDeadLater,
        sleepDead,
      ]);
      expect(await dao.lastDeadErrors(), isEmpty);
    });

    test('reset one kind and leave the others dead', () async {
      final reset = await dao.resetDead(kind: HealthRecordKind.sleep);

      expect(reset, 1);
      final rows = {for (final row in await dao.all()) row.id: row};
      expect(rows[sleepDead]?.status, OutboxStatus.pending);
      expect(rows[heartDead]?.status, OutboxStatus.dead);
      expect(rows[heartDead]?.attempts, 8);
      expect(rows[heartDeadLater]?.status, OutboxStatus.dead);
      expect(await dao.resetDead(kind: HealthRecordKind.spo2), 0);
    });
  });

  group('write toggles', () {
    late HealthOutboxDao dao;

    Future<int> add(RecordKind kind) => dao.enqueue(
      kind: kind,
      deviceId: ringId,
      from: nightStart,
      to: syncNow,
      recordCount: 5,
      at: syncNow,
    );

    setUp(() => dao = HealthOutboxDao(memoryDatabase()));

    test('disabling moves only that type and only unfinished rows', () async {
      final queued = await add(RecordKind.heartRate);
      final retrying = await add(RecordKind.heartRate);
      final done = await add(RecordKind.heartRate);
      final dead = await add(RecordKind.heartRate);
      final other = await add(RecordKind.sleep);
      await dao.markFailed(
        retrying,
        error: 'busy',
        at: syncNow,
        nextAttemptAt: syncNow.add(const Duration(minutes: 5)),
      );
      await dao.markDone(done, at: syncNow);
      await dao.markDead(dead, error: 'gone', at: syncNow);

      final moved = await dao.disablePending(
        HealthRecordKind.heartRate,
        at: syncNow,
      );

      expect(moved, 2);
      final status = {for (final row in await dao.all()) row.id: row.status};
      expect(status[queued], OutboxStatus.disabled);
      expect(status[retrying], OutboxStatus.disabled);
      expect(status[done], OutboxStatus.done);
      expect(status[dead], OutboxStatus.dead);
      expect(status[other], OutboxStatus.pending);
      expect((await dao.due(syncNow)).map((e) => e.id), [other]);
    });

    test('restoring puts held rows back as fresh pending work', () async {
      final held = await add(RecordKind.heartRate);
      await dao.markFailed(
        held,
        error: 'busy',
        at: syncNow,
        nextAttemptAt: syncNow.add(const Duration(minutes: 5)),
      );
      await dao.disablePending(HealthRecordKind.heartRate, at: syncNow);

      final moved = await dao.restoreDisabled(HealthRecordKind.heartRate);

      expect(moved, 1);
      final row = (await dao.all()).single;
      expect(row.status, OutboxStatus.pending);
      expect(row.attempts, 0);
      expect(row.lastError, isNull);
      expect(row.completedAtUtcMs, isNull);
      expect((await dao.due(syncNow)).map((e) => e.id), [held]);
    });

    test('restoring leaves another type held', () async {
      await add(RecordKind.heartRate);
      await add(RecordKind.sleep);
      await dao.disablePending(HealthRecordKind.heartRate, at: syncNow);
      await dao.disablePending(HealthRecordKind.sleep, at: syncNow);

      await dao.restoreDisabled(HealthRecordKind.sleep);

      final status = {for (final row in await dao.all()) row.kind: row.status};
      expect(status[HealthRecordKind.heartRate], OutboxStatus.disabled);
      expect(status[HealthRecordKind.sleep], OutboxStatus.pending);
    });
  });
}
