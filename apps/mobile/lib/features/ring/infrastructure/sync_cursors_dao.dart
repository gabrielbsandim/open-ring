import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/database/tables/ring_tables.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/core/records/record_kind.dart';

part 'sync_cursors_dao.g.dart';

@DriftAccessor(tables: [SyncCursors])
class SyncCursorsDao extends DatabaseAccessor<AppDatabase>
    with _$SyncCursorsDaoMixin {
  new(super.attachedDatabase);

  Future<Map<RecordKind, DateTime>> cursorsFor(String deviceId) async {
    final rows = await (select(
      syncCursors,
    )..where((c) => c.deviceId.equals(deviceId))).get();
    return {for (final row in rows) row.kind: fromUtcMs(row.cursorUtcMs)};
  }

  Future<void> advance(
    String deviceId,
    Map<RecordKind, DateTime> cursors, {
    required DateTime at,
  }) => transaction(() async {
    for (final MapEntry(key: kind, value: cursor) in cursors.entries) {
      await into(syncCursors).insert(
        SyncCursorsCompanion.insert(
          deviceId: deviceId,
          kind: kind,
          cursorUtcMs: cursor.utcMs,
          updatedAtUtcMs: at.utcMs,
        ),
        onConflict: DoUpdate.withExcluded(
          (old, excluded) => SyncCursorsCompanion.custom(
            cursorUtcMs: excluded.cursorUtcMs,
            updatedAtUtcMs: excluded.updatedAtUtcMs,
          ),
          where: (old, excluded) =>
              old.cursorUtcMs.isSmallerThan(excluded.cursorUtcMs),
        ),
      );
    }
  });
}
