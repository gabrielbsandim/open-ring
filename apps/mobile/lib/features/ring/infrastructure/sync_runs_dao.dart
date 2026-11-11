import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/database/tables/ring_tables.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/ring/domain/sync_run.dart';
import 'package:ring_driver/ring_driver.dart';

part 'sync_runs_dao.g.dart';

@DriftAccessor(tables: [SyncRuns])
class SyncRunsDao extends DatabaseAccessor<AppDatabase>
    with _$SyncRunsDaoMixin {
  new(super.attachedDatabase, {this.keep = defaultKeep});

  static const defaultKeep = 240;
  static const shown = 20;

  final int keep;

  Future<void> record(String deviceId, SyncRun run) => transaction(() async {
    await into(syncRuns).insert(
      SyncRunsCompanion.insert(
        deviceId: deviceId,
        atUtcMs: run.at.utcMs,
        outcome: run.outcome.name,
        kinds: Value(
          RecordKind.values
              .where(run.kinds.contains)
              .map((kind) => kind.name)
              .join(','),
        ),
        recordCount: Value(run.recordCount),
        batteryPercent: Value(run.battery?.percent),
        batteryCharging: Value(run.battery?.charging),
        failures: Value(
          RingCapability.values
              .where(run.failures.contains)
              .map((capability) => capability.name)
              .join(','),
        ),
        heartRateIntervalSeenMinutes: Value(
          run.heartRateIntervalSeen?.inMinutes,
        ),
      ),
    );
    final kept = selectOnly(syncRuns)
      ..addColumns([syncRuns.id])
      ..where(syncRuns.deviceId.equals(deviceId))
      ..orderBy([OrderingTerm.desc(syncRuns.id)])
      ..limit(keep);
    await (delete(syncRuns)
          ..where((r) => r.deviceId.equals(deviceId) & r.id.isNotInQuery(kept)))
        .go();
  });

  Future<List<SyncRun>> recent(String deviceId) async {
    final rows =
        await (select(syncRuns)
              ..where((r) => r.deviceId.equals(deviceId))
              ..orderBy([(r) => OrderingTerm.desc(r.id)])
              ..limit(shown))
            .get();
    return [for (final row in rows) _run(row)];
  }

  static SyncRun _run(SyncRunRow row) => SyncRun(
    at: fromUtcMs(row.atUtcMs),
    outcome:
        SyncRunOutcome.values.asNameMap()[row.outcome] ??
        SyncRunOutcome.stopped,
    kinds: {
      for (final name in row.kinds.split(','))
        ?RecordKind.values.asNameMap()[name],
    },
    recordCount: row.recordCount,
    battery: switch ((row.batteryPercent, row.batteryCharging)) {
      (final int percent, final bool charging) => BatteryStatus(
        percent: percent,
        charging: charging,
      ),
      _ => null,
    },
    failures: {
      for (final name in row.failures.split(','))
        ?RingCapability.values.asNameMap()[name],
    },
    heartRateIntervalSeen: switch (row.heartRateIntervalSeenMinutes) {
      final int minutes => Duration(minutes: minutes),
      null => null,
    },
  );
}
