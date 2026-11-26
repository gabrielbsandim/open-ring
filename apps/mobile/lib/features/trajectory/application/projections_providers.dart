import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_projection.dart';

final class GradedProjection {
  const new({required this.projection, this.grade, this.actualKg});

  final TrajectoryProjection projection;
  final ProjectionGrade? grade;
  final double? actualKg;

  LocalDate get due => projection.monday.addDays(trajectoryFirmDays);
}

/// Every stored projection, newest Monday first, graded once its day came.
final projectionsProvider = FutureProvider<List<GradedProjection>>((ref) async {
  ref.watch(dataRevisionProvider);
  final today = ref.watch(currentDateProvider);
  // The view stores this Monday's band, so read the rows after it.
  await ref.watch(trajectoryViewProvider.future);
  final rows = await ref.read(projectionStoreProvider).all();
  final summary = await ref.watch(weightSummaryProvider.future);
  final daily = summary?.daily ?? const <DailyValue>[];
  return [for (final row in rows.reversed) _graded(row, today, daily)];
});

GradedProjection _graded(
  TrajectoryProjection row,
  LocalDate today,
  List<DailyValue> daily,
) {
  final result = gradeProjection(
    monday: row.monday,
    low: row.lowKg,
    high: row.highKg,
    today: today,
    weighIns: daily,
  );
  return GradedProjection(
    projection: row,
    grade: result?.grade,
    actualKg: result?.actualKg,
  );
}
