import 'dart:isolate';
import 'dart:ui';

import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/workout/domain/workout_recovery.dart';

/// Marks a live start in the name server, one map for every engine in the
/// process, so recovery in a second engine skips it.
final class IsolateLiveWorkoutRegistry implements LiveWorkoutRegistry {
  @override
  void markLive(DateTime start) {
    // Only the name matters, so the port is closed at once and holds nothing.
    final port = RawReceivePort();
    IsolateNameServer.registerPortWithName(port.sendPort, _nameOf(start));
    port.close();
  }

  @override
  void clear(DateTime start) =>
      IsolateNameServer.removePortNameMapping(_nameOf(start));

  @override
  bool isLive(DateTime start) =>
      IsolateNameServer.lookupPortByName(_nameOf(start)) != null;

  static String _nameOf(DateTime start) =>
      'openring.workout.live.${start.utcMs}';
}
