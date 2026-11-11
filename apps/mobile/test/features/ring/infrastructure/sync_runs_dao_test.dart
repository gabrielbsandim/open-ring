import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/ring/domain/sync_run.dart';
import 'package:open_ring/features/ring/infrastructure/sync_runs_dao.dart';

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
}
