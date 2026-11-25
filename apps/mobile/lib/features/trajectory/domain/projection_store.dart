import 'package:open_ring/features/trajectory/domain/trajectory_projection.dart';

abstract interface class ProjectionStore {
  /// Stores [projection] unless its Monday already has one, and says whether
  /// it did.
  Future<bool> insertIfAbsent(TrajectoryProjection projection);

  /// Every stored projection, oldest Monday first.
  Future<List<TrajectoryProjection>> all();

  Future<int> deleteAll();
}
