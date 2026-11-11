import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/activity/infrastructure/activity_buckets_dao.dart';

final class DriftActivityHistoryReader implements ActivityHistoryReader {
  new(AppDatabase db) : _dao = ActivityBucketsDao(db);

  final ActivityBucketsDao _dao;

  @override
  Future<List<ActivitySlot>> activitySlots({
    required LocalDate from,
    required LocalDate to,
  }) async {
    final rows = await _dao.bucketsOnLocalDates(from: from, to: to);
    return [for (final row in rows) slotOf(row)];
  }

  @override
  Future<List<DailyActivity>> dailyActivity({
    required LocalDate from,
    required LocalDate to,
  }) async {
    final byDate = <LocalDate, List<ActivitySlot>>{};
    for (final slot in await activitySlots(from: from, to: to)) {
      byDate.putIfAbsent(slot.date, () => []).add(slot);
    }
    final dates = byDate.keys.toList()..sort((a, b) => a.compareTo(b));
    return [for (final date in dates) _total(date, byDate[date]!)];
  }

  static ActivitySlot slotOf(ActivityBucketRow row) => ActivitySlot(
    start: utcInstant(row.startUtcMs),
    utcOffset: offsetOf(row.offsetMinutes),
    duration: Duration(seconds: row.durationSeconds),
    steps: row.steps,
    activeKilocalories: row.activeKilocalories,
    distanceMeters: row.distanceMeters.toDouble(),
  );

  static DailyActivity _total(LocalDate date, List<ActivitySlot> slots) =>
      DailyActivity(
        date: date,
        steps: slots.fold(0, (sum, s) => sum + s.steps),
        activeKilocalories: slots.fold(
          0,
          (sum, s) => sum + s.activeKilocalories,
        ),
        distanceMeters: slots.fold(0, (sum, s) => sum + s.distanceMeters),
      );
}
