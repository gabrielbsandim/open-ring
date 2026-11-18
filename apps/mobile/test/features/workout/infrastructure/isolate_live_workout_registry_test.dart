import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/workout/infrastructure/isolate_live_workout_registry.dart';

import '../../../helpers/open_workout_fakes.dart';

String nameOf() => 'openring.workout.live.${openStart.utcMs}';

// What an isolate that died without clearing leaves: a name whose port no
// longer answers.
void deadMark() {
  final port = ReceivePort();
  IsolateNameServer.registerPortWithName(port.sendPort, nameOf());
  port.close();
}

void main() {
  late IsolateLiveWorkoutRegistry registry;

  setUp(() => registry = IsolateLiveWorkoutRegistry());

  tearDown(() => registry.clear(openStart));

  test('markLive registers the start under the process wide name', () async {
    registry.markLive(openStart);

    expect(IsolateNameServer.lookupPortByName(nameOf()), isA<SendPort>());
    expect(await registry.isLive(openStart), isTrue);
  });

  test('clear removes the name', () async {
    registry
      ..markLive(openStart)
      ..clear(openStart);

    expect(IsolateNameServer.lookupPortByName(nameOf()), isNull);
    expect(await registry.isLive(openStart), isFalse);
  });

  test('a start nobody marked is not live', () async {
    expect(await registry.isLive(openStartAfter(5)), isFalse);
  });

  test('another registry in the same process sees the mark', () async {
    registry.markLive(openStart);

    expect(await IsolateLiveWorkoutRegistry().isLive(openStart), isTrue);
  });

  test('clearing a start that was never marked does nothing', () {
    expect(() => registry.clear(openStartAfter(5)), returnsNormally);
  });

  test('a mark whose port no longer answers is not live and is '
      'dropped', () async {
    deadMark();

    expect(await registry.isLive(openStart), isFalse);
    expect(IsolateNameServer.lookupPortByName(nameOf()), isNull);
  });

  test('a live mark still answers after another start is checked', () async {
    registry.markLive(openStart);

    expect(await registry.isLive(openStartAfter(5)), isFalse);
    expect(await registry.isLive(openStart), isTrue);
    expect(await registry.isLive(openStart), isTrue);
  });

  test('marking again replaces a dead mark with one that answers', () async {
    deadMark();

    registry.markLive(openStart);

    expect(await registry.isLive(openStart), isTrue);
  });
}
