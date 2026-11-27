import 'package:drift/drift.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/trajectory/domain/projection_store.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_projection.dart';

final class DriftProjectionStore implements ProjectionStore {
  new(this._db);

  final AppDatabase _db;

  @override
  Future<bool> insertIfAbsent(TrajectoryProjection projection) async {
    _check(projection);
    final row = await _db
        .into(_db.trajectoryProjections)
        .insertReturningOrNull(
          TrajectoryProjectionsCompanion.insert(
            monday: projection.monday.iso,
            trendKg: projection.trendKg,
            rateKgPerWeek: projection.rateKgPerWeek,
            lowKg: projection.lowKg,
            midKg: projection.midKg,
            highKg: projection.highKg,
            createdAtUtcMs: projection.createdAt.toUtc().millisecondsSinceEpoch,
          ),
          onConflict: DoNothing(),
        );
    return row != null;
  }

  @override
  Future<List<TrajectoryProjection>> all() async {
    final query = _db.select(_db.trajectoryProjections)
      ..orderBy([(row) => OrderingTerm.asc(row.monday)]);
    return [for (final row in await query.get()) _projection(row)];
  }

  @override
  Future<int> deleteAll() => _db.delete(_db.trajectoryProjections).go();

  static void _check(TrajectoryProjection projection) {
    final monday = projection.monday;
    if (mondayOf(monday) != monday) {
      throw ArgumentError.value(monday.iso, 'monday', 'must be a Monday');
    }
    if (projection.lowKg > projection.midKg) {
      throw ArgumentError('lowKg must not be above midKg');
    }
    if (projection.midKg > projection.highKg) {
      throw ArgumentError('midKg must not be above highKg');
    }
  }

  static TrajectoryProjection _projection(TrajectoryProjectionRow row) =>
      TrajectoryProjection(
        monday: LocalDate.tryParse(row.monday)!,
        trendKg: row.trendKg,
        rateKgPerWeek: row.rateKgPerWeek,
        lowKg: row.lowKg,
        midKg: row.midKg,
        highKg: row.highKg,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row.createdAtUtcMs,
          isUtc: true,
        ),
      );
}
