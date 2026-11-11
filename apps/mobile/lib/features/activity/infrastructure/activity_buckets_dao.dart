import 'package:drift/drift.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';

class ActivityBucketsDao extends DatabaseAccessor<AppDatabase> {
  new(super.attachedDatabase);

  // A bucket belongs to the local date of its own start, read with the offset
  // the phone had when the ring recorded it, so the filter runs on wall time.
  Future<List<ActivityBucketRow>> bucketsOnLocalDates({
    required LocalDate from,
    required LocalDate to,
  }) {
    final table = attachedDatabase.activityBuckets;
    final wallMs =
        table.startUtcMs +
        table.offsetMinutes *
            const Constant<int>(Duration.millisecondsPerMinute);
    return (select(table)
          ..where(
            (_) =>
                wallMs.isBiggerOrEqualValue(_midnightMs(from)) &
                wallMs.isSmallerThanValue(_midnightMs(to.addDays(1))),
          )
          ..orderBy([(b) => OrderingTerm.asc(b.startUtcMs)]))
        .get();
  }

  static int _midnightMs(LocalDate date) =>
      DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch;
}
