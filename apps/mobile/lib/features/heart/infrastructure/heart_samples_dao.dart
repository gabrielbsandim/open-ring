import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';

class HeartSamplesDao extends DatabaseAccessor<AppDatabase> {
  new(super.attachedDatabase);

  Future<List<HrSampleRow>> heartRate(DateTime from, DateTime to) =>
      (select(attachedDatabase.hrSamples)
            ..where((s) => _within(s.atUtcMs, from, to))
            ..orderBy([(s) => OrderingTerm.asc(s.atUtcMs)]))
          .get();

  Future<List<HrvSampleRow>> hrv(DateTime from, DateTime to) =>
      (select(attachedDatabase.hrvSamples)
            ..where((s) => _within(s.atUtcMs, from, to))
            ..orderBy([(s) => OrderingTerm.asc(s.atUtcMs)]))
          .get();

  Future<List<Spo2SampleRow>> spo2(DateTime from, DateTime to) =>
      (select(attachedDatabase.spo2Samples)
            ..where((s) => _within(s.atUtcMs, from, to))
            ..orderBy([(s) => OrderingTerm.asc(s.atUtcMs)]))
          .get();

  Future<List<StressSampleRow>> stress(DateTime from, DateTime to) =>
      (select(attachedDatabase.stressSamples)
            ..where((s) => _within(s.atUtcMs, from, to))
            ..orderBy([(s) => OrderingTerm.asc(s.atUtcMs)]))
          .get();

  static Expression<bool> _within(
    Expression<int> at,
    DateTime from,
    DateTime to,
  ) => at.isBiggerOrEqualValue(from.utcMs) & at.isSmallerThanValue(to.utcMs);
}
