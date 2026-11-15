import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/domain/day_tag_store.dart';

final class DriftDayTagStore implements DayTagStore {
  new(this._db);

  final AppDatabase _db;

  @override
  Future<Map<LocalDate, DayTag>> all() async {
    final rows = await _db.select(_db.dayTags).get();
    return {
      for (final row in rows)
        if ((LocalDate.tryParse(row.date), DayTag.tryParse(row.tag)) case (
          final date?,
          final tag?,
        ))
          date: tag,
    };
  }

  @override
  Future<bool> put(LocalDate date, DayTag tag, {required DateTime now}) =>
      _db.transaction(() async {
        final stored = await (_db.select(
          _db.dayTags,
        )..where((row) => row.date.equals(date.iso))).getSingleOrNull();
        if (stored?.tag == tag.name) return false;
        await _db
            .into(_db.dayTags)
            .insertOnConflictUpdate(
              DayTagsCompanion.insert(
                date: date.iso,
                tag: tag.name,
                updatedAtUtcMs: now.millisecondsSinceEpoch,
              ),
            );
        return true;
      });

  @override
  Future<bool> remove(LocalDate date) async {
    final removed = await (_db.delete(
      _db.dayTags,
    )..where((row) => row.date.equals(date.iso))).go();
    return removed > 0;
  }
}
