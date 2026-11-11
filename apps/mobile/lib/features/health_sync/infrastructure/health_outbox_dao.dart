import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/database/tables/health_tables.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_outbox_store.dart';

part 'health_outbox_dao.g.dart';

@DriftAccessor(tables: [HealthOutbox])
class HealthOutboxDao extends DatabaseAccessor<AppDatabase>
    with _$HealthOutboxDaoMixin
    implements HealthOutboxStore, DeadOutboxStore, HealthWriteToggleStore {
  new(super.attachedDatabase);

  Future<int> enqueue({
    required RecordKind kind,
    required String? deviceId,
    required DateTime from,
    required DateTime to,
    required int recordCount,
    required DateTime at,
  }) => _insert(
    kind: HealthRecordKind.ofRing(kind),
    deviceId: deviceId,
    from: from,
    to: to,
    recordCount: recordCount,
    at: at,
  );

  Future<int> enqueueWorkout({
    required DateTime start,
    required DateTime end,
    required DateTime at,
    String? deviceId,
  }) => _insert(
    kind: HealthRecordKind.workout,
    deviceId: deviceId,
    from: start,
    to: end,
    recordCount: 1,
    at: at,
  );

  Future<int> _insert({
    required HealthRecordKind kind,
    required String? deviceId,
    required DateTime from,
    required DateTime to,
    required int recordCount,
    required DateTime at,
  }) => into(healthOutbox).insert(
    HealthOutboxCompanion.insert(
      kind: kind,
      deviceId: Value(deviceId),
      fromUtcMs: from.utcMs,
      toUtcMs: to.utcMs,
      recordCount: recordCount,
      enqueuedAtUtcMs: at.utcMs,
    ),
  );

  Future<List<HealthOutboxRow>> pending() =>
      (select(healthOutbox)
            ..where((o) => o.status.equalsValue(OutboxStatus.pending))
            ..orderBy([(o) => OrderingTerm.asc(o.id)]))
          .get();

  Future<List<HealthOutboxRow>> all() =>
      (select(healthOutbox)..orderBy([(o) => OrderingTerm.asc(o.id)])).get();

  @override
  Future<List<OutboxEntry>> due(DateTime now) async {
    final rows =
        await (select(healthOutbox)
              ..where(
                (o) =>
                    o.status.equalsValue(OutboxStatus.pending) &
                    (o.nextAttemptAtUtcMs.isNull() |
                        o.nextAttemptAtUtcMs.isSmallerOrEqualValue(now.utcMs)),
              )
              ..orderBy([(o) => OrderingTerm.asc(o.id)]))
            .get();
    return [
      for (final row in rows)
        OutboxEntry(
          id: row.id,
          kind: row.kind,
          deviceId: row.deviceId,
          from: fromUtcMs(row.fromUtcMs),
          to: fromUtcMs(row.toUtcMs),
          enqueuedAt: fromUtcMs(row.enqueuedAtUtcMs),
          attempts: row.attempts,
        ),
    ];
  }

  @override
  Future<void> markDone(int id, {required DateTime at}) =>
      _finish(id, OutboxStatus.done, at);

  @override
  Future<void> markNotApplicable(int id, {required DateTime at}) =>
      _finish(id, OutboxStatus.notApplicable, at);

  @override
  Future<void> markDisabled(int id, {required DateTime at}) =>
      _finish(id, OutboxStatus.disabled, at);

  @override
  Future<int> disablePending(HealthRecordKind kind, {required DateTime at}) =>
      (update(healthOutbox)..where(
            (o) =>
                o.status.equalsValue(OutboxStatus.pending) &
                o.kind.equalsValue(kind),
          ))
          .write(
            HealthOutboxCompanion(
              status: const Value(OutboxStatus.disabled),
              completedAtUtcMs: Value(at.utcMs),
              nextAttemptAtUtcMs: const Value(null),
            ),
          );

  @override
  Future<int> restoreDisabled(HealthRecordKind kind) =>
      (update(healthOutbox)..where(
            (o) =>
                o.status.equalsValue(OutboxStatus.disabled) &
                o.kind.equalsValue(kind),
          ))
          .write(
            const HealthOutboxCompanion(
              status: Value(OutboxStatus.pending),
              attempts: Value(0),
              lastError: Value(null),
              completedAtUtcMs: Value(null),
              nextAttemptAtUtcMs: Value(null),
            ),
          );

  @override
  Future<void> markFailed(
    int id, {
    required String error,
    required DateTime at,
    required DateTime nextAttemptAt,
  }) => _attempt(
    id,
    error,
    at,
    status: OutboxStatus.pending,
    nextAttemptAt: nextAttemptAt,
  );

  @override
  Future<void> markDead(
    int id, {
    required String error,
    required DateTime at,
  }) => _attempt(id, error, at, status: OutboxStatus.dead);

  Future<void> _finish(int id, OutboxStatus status, DateTime at) =>
      (update(healthOutbox)..where((o) => o.id.equals(id))).write(
        HealthOutboxCompanion(
          status: Value(status),
          completedAtUtcMs: Value(at.utcMs),
          lastAttemptAtUtcMs: Value(at.utcMs),
          nextAttemptAtUtcMs: const Value(null),
        ),
      );

  Future<void> _attempt(
    int id,
    String error,
    DateTime at, {
    required OutboxStatus status,
    DateTime? nextAttemptAt,
  }) => (update(healthOutbox)..where((o) => o.id.equals(id))).write(
    HealthOutboxCompanion.custom(
      attempts: healthOutbox.attempts + const Constant(1),
      lastError: Variable(error),
      lastAttemptAtUtcMs: Variable(at.utcMs),
      status: Variable(status.name),
      nextAttemptAtUtcMs: Variable(nextAttemptAt?.utcMs),
    ),
  );

  @override
  Future<Map<HealthRecordKind, String?>> lastDeadErrors() async {
    final rows =
        await (select(healthOutbox)
              ..where((o) => o.status.equalsValue(OutboxStatus.dead))
              ..orderBy([
                (o) => OrderingTerm.asc(o.lastAttemptAtUtcMs),
                (o) => OrderingTerm.asc(o.id),
              ]))
            .get();
    return {for (final row in rows) row.kind: row.lastError};
  }

  @override
  Future<int> resetDead({HealthRecordKind? kind}) =>
      (update(healthOutbox)..where(
            (o) =>
                o.status.equalsValue(OutboxStatus.dead) &
                (kind == null
                    ? const Constant(true)
                    : o.kind.equalsValue(kind)),
          ))
          .write(
            const HealthOutboxCompanion(
              status: Value(OutboxStatus.pending),
              attempts: Value(0),
              lastError: Value(null),
              nextAttemptAtUtcMs: Value(null),
            ),
          );
}
