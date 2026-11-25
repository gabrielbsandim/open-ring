import 'package:metrics/metrics.dart';
import 'package:open_ring/features/trajectory/domain/projection_store.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_projection.dart';

final class InMemoryProjectionStore implements ProjectionStore {
  final Map<LocalDate, TrajectoryProjection> _rows = {};

  @override
  Future<bool> insertIfAbsent(TrajectoryProjection projection) async {
    if (_rows.containsKey(projection.monday)) return false;
    _rows[projection.monday] = projection;
    return true;
  }

  @override
  Future<List<TrajectoryProjection>> all() async =>
      _rows.values.toList()..sort((a, b) => a.monday.compareTo(b.monday));

  @override
  Future<int> deleteAll() async {
    final removed = _rows.length;
    _rows.clear();
    return removed;
  }
}
