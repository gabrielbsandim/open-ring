import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/ring/domain/sync_run.dart';
import 'package:open_ring/features/ring/infrastructure/sync_runs_dao.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';
import '../../../helpers/sync_fixtures.dart';

void main() {
  test('keeps the outcome, kinds and count, newest first', () async {
    final dao = SyncRunsDao(await pairedDatabase());
    await dao.record(
      ringId,
      SyncRun(at: syncNow, outcome: SyncRunOutcome.unreachable),
    );
    final later = syncNow.add(const Duration(hours: 1));
    await dao.record(
      ringId,
      SyncRun(
        at: later,
        outcome: SyncRunOutcome.partial,
        kinds: const {RecordKind.stress, RecordKind.heartRate},
        recordCount: 46,
      ),
    );

    final runs = await dao.recent(ringId);

    expect(runs.map((r) => (r.at, r.outcome, r.recordCount)), [
      (later, SyncRunOutcome.partial, 46),
      (syncNow, SyncRunOutcome.unreachable, 0),
    ]);
    expect(runs.first.kinds, {RecordKind.heartRate, RecordKind.stress});
    expect(runs.last.kinds, isEmpty);
  });

  test('drops the oldest runs past the kept count', () async {
    final dao = SyncRunsDao(await pairedDatabase(), keep: 3);
    for (var hour = 0; hour < 5; hour++) {
      await dao.record(
        ringId,
        SyncRun(
          at: syncNow.add(Duration(hours: hour)),
          outcome: SyncRunOutcome.completed,
        ),
      );
    }

    final runs = await dao.recent(ringId);

    expect(runs.map((r) => r.at.hour), [12, 11, 10]);
  });

  test('keeps the battery, the failures and the interval seen', () async {
    final dao = SyncRunsDao(await pairedDatabase());
    await dao.record(
      ringId,
      SyncRun(
        at: syncNow,
        outcome: SyncRunOutcome.partial,
        battery: const BatteryStatus(percent: 61, charging: false),
        failures: const {RingCapability.spo2, RingCapability.heartRateInterval},
        heartRateIntervalSeen: const Duration(minutes: 30),
      ),
    );

    final run = (await dao.recent(ringId)).single;

    expect((run.battery?.percent, run.battery?.charging), (61, false));
    expect(run.failures, {
      RingCapability.heartRateInterval,
      RingCapability.spo2,
    });
    expect(run.heartRateIntervalSeen, const Duration(minutes: 30));
  });

  test('a run without a battery read keeps none', () async {
    final dao = SyncRunsDao(await pairedDatabase());
    await dao.record(
      ringId,
      SyncRun(at: syncNow, outcome: SyncRunOutcome.unreachable),
    );

    final run = (await dao.recent(ringId)).single;

    expect(run.battery, isNull);
    expect(run.failures, isEmpty);
    expect(run.heartRateIntervalSeen, isNull);
  });

  test('keeps more runs than the log shows', () async {
    final db = await pairedDatabase();
    final dao = SyncRunsDao(db);
    for (var hour = 0; hour < SyncRunsDao.shown + 2; hour++) {
      await dao.record(
        ringId,
        SyncRun(
          at: syncNow.add(Duration(hours: hour)),
          outcome: SyncRunOutcome.completed,
        ),
      );
    }

    expect(await dao.recent(ringId), hasLength(SyncRunsDao.shown));
    expect(
      await db.select(db.syncRuns).get(),
      hasLength(SyncRunsDao.shown + 2),
    );
  });
}
