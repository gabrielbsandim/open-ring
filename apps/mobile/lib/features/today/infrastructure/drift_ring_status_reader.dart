import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/today/infrastructure/ring_status_dao.dart';

final class DriftRingStatusReader implements RingStatusReader {
  new(AppDatabase db) : _dao = RingStatusDao(db);

  final RingStatusDao _dao;

  @override
  Future<RingStatus> status() async {
    final row = await _dao.latestPaired();
    if (row == null) return RingStatus.unpaired;
    return RingStatus(
      paired: true,
      name: row.name,
      model: row.model,
      firmware: row.firmware,
      lastSyncAt: _instant(row.lastSyncAtUtcMs),
      batteryPercent: row.batteryPercent,
      batteryCharging: row.batteryCharging,
      batteryAt: _instant(row.batteryAtUtcMs),
    );
  }

  static DateTime? _instant(int? utcMs) => switch (utcMs) {
    null => null,
    final ms => utcInstant(ms),
  };
}
