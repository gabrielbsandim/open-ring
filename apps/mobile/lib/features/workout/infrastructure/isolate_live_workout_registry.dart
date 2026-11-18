import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/workout/domain/workout_recovery.dart';

const liveWorkoutAnswerWithin = Duration(seconds: 1);

/// Marks a live start in the name server, one map for every engine in the
/// process, so recovery in a second engine skips it.
final class IsolateLiveWorkoutRegistry implements LiveWorkoutRegistry {
  final Map<int, ReceivePort> _ports = {};

  @override
  void markLive(DateTime start) {
    final port = ReceivePort()..listen(_answer);
    final name = _nameOf(start);
    IsolateNameServer.removePortNameMapping(name);
    IsolateNameServer.registerPortWithName(port.sendPort, name);
    _ports.remove(start.utcMs)?.close();
    _ports[start.utcMs] = port;
  }

  @override
  void clear(DateTime start) {
    IsolateNameServer.removePortNameMapping(_nameOf(start));
    _ports.remove(start.utcMs)?.close();
  }

  // The name server keeps a name after its isolate dies, so only a port
  // that answers proves the workout is still recording.
  @override
  Future<bool> isLive(DateTime start) async {
    final name = _nameOf(start);
    final port = IsolateNameServer.lookupPortByName(name);
    if (port == null) return false;
    final reply = ReceivePort();
    port.send(reply.sendPort);
    try {
      return await reply.first.timeout(liveWorkoutAnswerWithin) == true;
    } on TimeoutException {
      _dropStale(name, port);
      return false;
    } finally {
      reply.close();
    }
  }

  static void _answer(Object? message) {
    if (message is SendPort) message.send(true);
  }

  static void _dropStale(String name, SendPort port) {
    if (IsolateNameServer.lookupPortByName(name) != port) return;
    IsolateNameServer.removePortNameMapping(name);
  }

  static String _nameOf(DateTime start) =>
      'openring.workout.live.${start.utcMs}';
}
