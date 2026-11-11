import 'package:drift/drift.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/sleep/domain/rem_reporting_reader.dart';
import 'package:ring_driver/ring_driver.dart';

final class DriftRemReportingReader implements RemReportingReader {
  const new(this._db);

  final AppDatabase _db;

  // A night is a session with asleep time, dated by its local end, so a
  // session the ring split in two still counts once.
  @override
  Future<RemReporting> pairedRing() async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(DISTINCT day) AS nights, '
          'COUNT(DISTINCT CASE WHEN rem THEN day END) AS rem_nights '
          'FROM (SELECT '
          '(s.end_utc_ms + s.offset_minutes * 60000) / 86400000 AS day, '
          'MAX(g.stage = ?) AS rem '
          'FROM sleep_sessions s JOIN sleep_segments g '
          'ON g.device_id = s.device_id '
          'AND g.session_start_utc_ms = s.start_utc_ms '
          'WHERE g.stage != ? AND s.device_id = '
          '(SELECT device_id FROM ring_devices '
          'ORDER BY paired_at_utc_ms DESC LIMIT 1) '
          'GROUP BY s.start_utc_ms)',
          variables: [
            Variable.withString(SleepStage.rem.name),
            Variable.withString(SleepStage.awake.name),
          ],
          readsFrom: {_db.sleepSessions, _db.sleepSegments, _db.ringDevices},
        )
        .getSingle();
    return RemReporting.observe(
      nights: row.read<int>('nights'),
      nightsWithRem: row.read<int>('rem_nights'),
    );
  }
}
