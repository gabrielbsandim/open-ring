import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';

class RingStatusDao extends DatabaseAccessor<AppDatabase> {
  new(super.attachedDatabase);

  Future<RingDeviceRow?> latestPaired() =>
      (select(attachedDatabase.ringDevices)
            ..where((d) => d.unpairedAtUtcMs.isNull())
            ..orderBy([(d) => OrderingTerm.desc(d.pairedAtUtcMs)])
            ..limit(1))
          .getSingleOrNull();
}
