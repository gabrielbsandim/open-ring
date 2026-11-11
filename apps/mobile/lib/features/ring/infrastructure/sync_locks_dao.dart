import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/database/tables/ring_tables.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/ring/domain/sync_lock.dart';

part 'sync_locks_dao.g.dart';

// A row, not a file lock: SQLite serializes this upsert across isolates and
// engines, while dart:io file locks are per process and both engines share one.
@DriftAccessor(tables: [SyncLocks])
class SyncLocksDao extends DatabaseAccessor<AppDatabase>
    with _$SyncLocksDaoMixin
    implements SyncLock {
  new(super.attachedDatabase, {this.name = ringSync});

  static const ringSync = 'ring_sync';
  static const healthOutbox = 'health_outbox';

  final String name;

  @override
  Future<bool> acquire(
    String owner, {
    required DateTime at,
    required Duration timeout,
  }) async {
    final row = await into(syncLocks).insertReturningOrNull(
      SyncLocksCompanion.insert(
        name: name,
        owner: owner,
        acquiredAtUtcMs: at.utcMs,
        expiresAtUtcMs: at.add(timeout).utcMs,
      ),
      onConflict: DoUpdate.withExcluded(
        (old, excluded) => SyncLocksCompanion.custom(
          owner: excluded.owner,
          acquiredAtUtcMs: excluded.acquiredAtUtcMs,
          expiresAtUtcMs: excluded.expiresAtUtcMs,
        ),
        where: (old, excluded) =>
            old.expiresAtUtcMs.isSmallerOrEqual(excluded.acquiredAtUtcMs),
      ),
    );
    return row?.owner == owner;
  }

  @override
  Future<void> release(String owner) => (delete(
    syncLocks,
  )..where((l) => l.name.equals(name) & l.owner.equals(owner))).go();

  Future<SyncLockRow?> current() =>
      (select(syncLocks)..where((l) => l.name.equals(name))).getSingleOrNull();
}
