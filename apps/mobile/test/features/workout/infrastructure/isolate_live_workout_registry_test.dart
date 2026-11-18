import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/workout/infrastructure/isolate_live_workout_registry.dart';

import '../../../helpers/open_workout_fakes.dart';

String nameOf() => 'openring.workout.live.${openStart.utcMs}';

void main() {
  late IsolateLiveWorkoutRegistry registry;

  setUp(() => registry = IsolateLiveWorkoutRegistry());

  tearDown(() => registry.clear(openStart));

  test('markLive registers the start under the process wide name', () {
    registry.markLive(openStart);

    expect(IsolateNameServer.lookupPortByName(nameOf()), isA<SendPort>());
    expect(registry.isLive(openStart), isTrue);
  });

  test('clear removes the name', () {
    registry
      ..markLive(openStart)
      ..clear(openStart);

    expect(IsolateNameServer.lookupPortByName(nameOf()), isNull);
    expect(registry.isLive(openStart), isFalse);
  });

  test('a start nobody marked is not live', () {
    expect(registry.isLive(openStartAfter(5)), isFalse);
  });

  test('another registry in the same process sees the mark', () {
    registry.markLive(openStart);

    expect(IsolateLiveWorkoutRegistry().isLive(openStart), isTrue);
  });

  test('clearing a start that was never marked does nothing', () {
    expect(() => registry.clear(openStartAfter(5)), returnsNormally);
  });
}
