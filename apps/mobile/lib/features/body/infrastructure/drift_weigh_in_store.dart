import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/domain/weigh_in_store.dart';

final class DriftWeighInStore implements WeighInStore {
  new(this._db);

  final AppDatabase _db;

  @override
  Future<List<WeighIn>> all() async {
    final query = _db.select(_db.weighIns)
      ..orderBy([
        (row) => OrderingTerm.desc(row.atUtcMs),
        (row) => OrderingTerm.desc(row.id),
      ]);
    return [for (final row in await query.get()) _weighIn(row)];
  }

  @override
  Future<WeighIn> add(WeighInDraft draft) async =>
      _weighIn(await _db.into(_db.weighIns).insertReturning(_columns(draft)));

  @override
  Future<bool> update(int id, WeighInDraft draft) async {
    final changed = await (_db.update(
      _db.weighIns,
    )..where((row) => row.id.equals(id))).write(_columns(draft));
    return changed > 0;
  }

  @override
  Future<bool> delete(int id) async {
    final removed = await (_db.delete(
      _db.weighIns,
    )..where((row) => row.id.equals(id))).go();
    return removed > 0;
  }

  @override
  Future<int> deleteAll() => _db.delete(_db.weighIns).go();

  @override
  Future<int> count() async => await _db.weighIns.count().getSingle();

  static WeighInsCompanion _columns(WeighInDraft draft) => WeighInsCompanion(
    atUtcMs: Value(draft.at.millisecondsSinceEpoch),
    offsetMinutes: Value(draft.offsetMinutes),
    kilograms: Value(roundKilograms(draft.kilograms)),
    bodyFatPercent: Value(draft.bodyFatPercent),
    waistCentimeters: Value(draft.waistCentimeters),
    source: Value(draft.source.name),
  );

  static WeighIn _weighIn(WeighInRow row) => WeighIn(
    id: row.id,
    at: DateTime.fromMillisecondsSinceEpoch(row.atUtcMs, isUtc: true),
    offsetMinutes: row.offsetMinutes,
    kilograms: row.kilograms,
    bodyFatPercent: row.bodyFatPercent,
    waistCentimeters: row.waistCentimeters,
    source:
        WeighInSource.values.asNameMap()[row.source] ?? WeighInSource.manual,
  );
}
