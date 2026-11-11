import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/sleep/domain/sleep_history_reader.dart';
import 'package:open_ring/features/sleep/infrastructure/sleep_history_dao.dart';
import 'package:ring_driver/ring_driver.dart';

final class DriftSleepHistoryReader implements SleepHistoryReader {
  new(AppDatabase db) : _dao = SleepHistoryDao(db);

  final SleepHistoryDao _dao;

  @override
  Future<List<SleepSpan>> sleepSpans({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _dao.segmentsOverlapping(from: from, to: to);
    return [for (final row in rows) spanOf(row)];
  }

  static SleepSpan spanOf(SleepSegmentRow row) => SleepSpan(
    start: utcInstant(row.startUtcMs),
    end: utcInstant(row.endUtcMs),
    phase: phaseOf(row.stage),
    utcOffset: offsetOf(row.offsetMinutes),
  );

  static SleepPhase phaseOf(SleepStage stage) => switch (stage) {
    SleepStage.light => SleepPhase.light,
    SleepStage.deep => SleepPhase.deep,
    SleepStage.rem => SleepPhase.rem,
    SleepStage.awake => SleepPhase.awake,
  };
}
