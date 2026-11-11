import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';

class SleepHistoryDao extends DatabaseAccessor<AppDatabase> {
  new(super.attachedDatabase);

  Future<List<SleepSegmentRow>> segmentsOverlapping({
    required DateTime from,
    required DateTime to,
  }) =>
      (select(attachedDatabase.sleepSegments)
            ..where(
              (s) =>
                  s.startUtcMs.isSmallerThanValue(to.utcMs) &
                  s.endUtcMs.isBiggerThanValue(from.utcMs),
            )
            ..orderBy([(s) => OrderingTerm.asc(s.startUtcMs)]))
          .get();
}
