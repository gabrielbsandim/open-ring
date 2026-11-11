import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/domain/location_fix.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/protocol_lab_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/workout_fakes.dart';

const pairedRing = RingStatus(
  paired: true,
  name: 'R09_C0FE',
  model: 'R09',
  batteryPercent: 68,
);

Future<void> pumpWorkout(
  WidgetTester tester,
  Widget screen,
  WorkoutRig rig, {
  LayoutCase c = const LayoutCase(
    scale: 1,
    brightness: Brightness.dark,
    locale: Locale('en'),
  ),
  RingStatus ring = pairedRing,
  Size size = phoneSize,
}) => pumpScaled(
  tester,
  screenHost(screen),
  textScaler: c.textScaler,
  brightness: c.brightness,
  locale: c.locale,
  size: size,
  overrides: [
    ...protocolLabOverrides(),
    ...ringOverrides(),
    ...rig.overrides(),
    ringStatusReaderProvider.overrideWithValue(FakeRingStatusReader(ring)),
  ],
);

ProviderContainer workoutContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

WorkoutController workoutOf(WidgetTester tester) =>
    workoutContainer(tester).read(workoutProvider.notifier);

const tallPhone = Size(360, 2400);

Future<void> settle(WidgetTester tester) =>
    expectNoLayoutOverflow(tester.pumpAndSettle);

// Stopping the workout streams completes outside the fake clock, so finish
// and discard need a real event-loop turn before the save state moves.
Future<void> flushStreams(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await settle(tester);
}

Future<void> finishWorkout(WidgetTester tester) async {
  unawaited(workoutOf(tester).finish());
  await flushStreams(tester);
}

Future<void> discardWorkout(WidgetTester tester) async {
  unawaited(workoutOf(tester).discard());
  await flushStreams(tester);
}

Future<void> startRunning(
  WidgetTester tester,
  WorkoutRig rig, {
  WorkoutType type = WorkoutType.running,
  int seconds = 90,
}) async {
  await workoutOf(tester).start(type, notice: testNotice);
  rig
    ..second(meters: 0)
    ..run(seconds);
}

const savedRunId = 7;

// 1.8 km north at 3 m/s with a one minute pause at 300 s and a 30 m climb.
SavedWorkout savedRun({
  int id = savedRunId,
  Duration startAfter = Duration.zero,
  WorkoutType type = WorkoutType.running,
  WorkoutHealthStatus health = WorkoutHealthStatus.sent,
}) {
  final start = workoutStart.add(startAfter);
  DateTime t(int seconds) => start.add(Duration(seconds: seconds));
  final session = WorkoutSession(
    type: type,
    profile: WorkoutProfile(
      zones: HeartRateZones(maxHeartRate: 190),
      weightKilograms: 70,
    ),
  )..start(start);
  var meters = 0.0;
  void move(int from, int to) {
    for (var s = from; s <= to; s++) {
      session
        ..addFix(
          LocationFix(
            at: t(s),
            latitude: -23.55 + meters / metersPerDegreeLatitude,
            longitude: -46.63,
            accuracyMeters: 5,
            altitudeMeters: 700 + meters / 60,
          ),
        )
        ..addHeartRate(120 + s % 50, t(s));
      meters += 3;
    }
  }

  move(0, 300);
  session
    ..pause(t(300))
    ..resume(t(360));
  move(360, 660);
  session.finish(t(660));
  return SavedWorkout(
    id: id,
    workout: session.finished(),
    utcOffset: Duration.zero,
    health: health,
  );
}
