import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_projection.dart';

/// The stored projections, oldest Monday first, for the module screen.
final trajectoryDataProvider = FutureProvider<List<TrajectoryProjection>>((
  ref,
) {
  ref.watch(dataRevisionProvider);
  return ref.watch(projectionStoreProvider).all();
});

final trajectoryDataEraserProvider = Provider<TrajectoryDataEraser>(
  TrajectoryDataEraser.new,
);

class TrajectoryDataEraser {
  const new(this._ref);

  final Ref _ref;

  /// Empties the stored projections. Weigh-ins stay in Body and the module
  /// stays on. False, with the error logged and nothing bumped, on a throw.
  Future<bool> clear() async {
    try {
      await _ref.read(projectionStoreProvider).deleteAll();
    } on Object catch (error) {
      debugPrint('Trajectory data was not deleted: $error');
      return false;
    }
    _ref.read(dataRevisionProvider.notifier).bump();
    return true;
  }
}
