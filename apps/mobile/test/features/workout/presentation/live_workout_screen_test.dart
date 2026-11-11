import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_state.dart';
import 'package:open_ring/features/workout/domain/live_heart_rate_source.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/live_workout_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/workout_fakes.dart';
import 'workout_scenarios.dart';

String _text(WidgetTester tester, Key key) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(Text),
        matchRoot: true,
      ),
    )
    .data!;

WorkoutState _state(WidgetTester tester) =>
    workoutContainer(tester).read(workoutProvider);

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a running workout shows the clock, link, GPS and HR zone', (
    tester,
  ) async {
    final rig = WorkoutRig();
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await startRunning(tester, rig, seconds: 60);
    await settle(tester);

    expect(find.text('Running'), findsOneWidget);
    expect(_text(tester, LiveWorkoutKeys.phase), 'In progress');
    expect(_text(tester, LiveWorkoutKeys.clock), '00:\u200B01:01');
    expect(find.text('Ring sending heart rate every second'), findsOneWidget);
    expect(find.text('GPS good'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(LiveWorkoutKeys.gps),
        matching: find.textContaining('GPS good'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('±5 m'), findsOneWidget);
    expect(find.byKey(LiveWorkoutKeys.map), findsOneWidget);
    expect(_text(tester, LiveWorkoutKeys.zoneCaption), 'Zone 4 · Threshold');
    expect(
      find.text(
        'Zones from your max heart rate of 184 bpm. Adjust it in Profile.',
      ),
      findsOneWidget,
    );
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('Current pace'), findsOneWidget);
    expect(find.text('Average pace'), findsOneWidget);
    expect(find.text('Energy'), findsOneWidget);
    expect(find.text('Average HR'), findsOneWidget);
    expect(find.text('Max HR'), findsOneWidget);
    expect(find.text('0.18'), findsOneWidget);
    expect(find.text('5:33'), findsOneWidget);
    expect(find.text('5:39'), findsOneWidget);
  });

  testWidgets('pause and resume follow the controller', (tester) async {
    final rig = WorkoutRig();
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await startRunning(tester, rig, seconds: 10);
    await settle(tester);

    await _tap(tester, LiveWorkoutKeys.toggle);
    expect(_state(tester).status, WorkoutStatus.paused);
    expect(_text(tester, LiveWorkoutKeys.phase), 'Paused');
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Ring connected'), findsOneWidget);

    rig.run(30);
    await settle(tester);
    expect(_text(tester, LiveWorkoutKeys.clock), '00:\u200B00:11');

    await _tap(tester, LiveWorkoutKeys.toggle);
    expect(_state(tester).status, WorkoutStatus.running);
    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets('end asks first, continue resumes the workout', (tester) async {
    final rig = WorkoutRig();
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await startRunning(tester, rig, seconds: 10);
    await settle(tester);

    await _tap(tester, LiveWorkoutKeys.end);
    expect(find.byKey(LiveWorkoutKeys.confirm), findsOneWidget);
    expect(find.text('End and save the workout?'), findsOneWidget);
    expect(_state(tester).status, WorkoutStatus.paused);
    expect(find.byKey(LiveWorkoutKeys.toggle), findsNothing);

    await _tap(tester, LiveWorkoutKeys.keepGoing);
    expect(find.byKey(LiveWorkoutKeys.confirm), findsNothing);
    expect(_state(tester).status, WorkoutStatus.running);
  });

  testWidgets('continue keeps a paused workout paused', (tester) async {
    final rig = WorkoutRig();
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await startRunning(tester, rig, seconds: 10);
    await settle(tester);

    await _tap(tester, LiveWorkoutKeys.toggle);
    await _tap(tester, LiveWorkoutKeys.end);
    await _tap(tester, LiveWorkoutKeys.keepGoing);

    expect(_state(tester).status, WorkoutStatus.paused);
  });

  testWidgets('save writes the workout and shows the saved card', (
    tester,
  ) async {
    final store = RecordingWorkoutStore();
    final rig = WorkoutRig(store: store);
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await startRunning(tester, rig, seconds: 120);
    await settle(tester);

    await _tap(tester, LiveWorkoutKeys.end);
    await _tap(tester, LiveWorkoutKeys.save);
    await flushStreams(tester);

    expect(store.saved, hasLength(1));
    expect(store.saved.single.type, WorkoutType.running);
    expect(find.byKey(LiveWorkoutKeys.saved), findsOneWidget);
    expect(find.text('Workout saved'), findsOneWidget);
    expect(find.byKey(LiveWorkoutKeys.summary), findsOneWidget);
    expect(_text(tester, LiveWorkoutKeys.phase), 'Finished');
    expect(find.byKey(LiveWorkoutKeys.heart), findsNothing);
    expect(rig.heartRate.listening, isFalse);
    expect(rig.location.listening, isFalse);
  });

  testWidgets('a failed save offers to save again', (tester) async {
    final store = RecordingWorkoutStore();
    final rig = WorkoutRig(store: FlakyWorkoutStore(store));
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await startRunning(tester, rig, seconds: 30);
    await settle(tester);

    await _tap(tester, LiveWorkoutKeys.end);
    await _tap(tester, LiveWorkoutKeys.save);
    await flushStreams(tester);
    expect(find.byKey(LiveWorkoutKeys.failed), findsOneWidget);
    expect(store.saved, isEmpty);

    await _tap(tester, LiveWorkoutKeys.retry);
    await flushStreams(tester);
    expect(find.byKey(LiveWorkoutKeys.saved), findsOneWidget);
    expect(store.saved, hasLength(1));
  });

  testWidgets('discard records nothing', (tester) async {
    final store = RecordingWorkoutStore();
    final rig = WorkoutRig(store: store);
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await startRunning(tester, rig, seconds: 30);
    await settle(tester);

    await _tap(tester, LiveWorkoutKeys.end);
    await _tap(tester, LiveWorkoutKeys.discard);
    await flushStreams(tester);

    expect(find.byKey(LiveWorkoutKeys.discarded), findsOneWidget);
    expect(store.saved, isEmpty);
    expect(_state(tester).status, WorkoutStatus.discarded);
  });

  testWidgets('without a fix the GPS chip searches and the map waits', (
    tester,
  ) async {
    final rig = WorkoutRig();
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await workoutOf(tester).start(WorkoutType.running, notice: testNotice);
    rig
      ..run(5, meters: null)
      ..second(meters: 3, accuracyMeters: 40);
    await settle(tester);

    expect(find.textContaining('Searching for GPS'), findsOneWidget);
    expect(
      find.text('The route appears here after the first good GPS fix.'),
      findsOneWidget,
    );
    expect(find.textContaining('±'), findsNothing);
  });

  testWidgets('a fair fix shows its accuracy, a stale one reads lost', (
    tester,
  ) async {
    final rig = WorkoutRig();
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await workoutOf(tester).start(WorkoutType.running, notice: testNotice);
    rig.second(meters: 0, accuracyMeters: 18);
    await settle(tester);
    expect(find.textContaining('GPS fair'), findsOneWidget);
    expect(find.textContaining('±18 m'), findsOneWidget);

    rig.run(20, meters: null);
    await settle(tester);
    expect(find.textContaining('GPS signal lost'), findsOneWidget);
  });

  testWidgets('a lost ring keeps the workout and says why HR is missing', (
    tester,
  ) async {
    final rig = WorkoutRig();
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await startRunning(tester, rig, seconds: 10);
    rig.heartRate.fail(
      const HeartRateUnavailable(HeartRateProblem.unreachable),
    );
    rig.run(15, bpm: null);
    await settle(tester);

    expect(find.text('Ring not reachable'), findsOneWidget);
    expect(
      _text(tester, LiveWorkoutKeys.zoneCaption),
      'Waiting for heart rate',
    );
    expect(
      find.text(
        'The ring stopped sending heart rate. The workout keeps recording.',
      ),
      findsOneWidget,
    );
    expect(_state(tester).status, WorkoutStatus.running);

    await _tap(tester, LiveWorkoutKeys.reconnect);
    await flushStreams(tester);
    expect(rig.heartRate.listens, 2);
    expect(find.text('Waiting for the ring'), findsOneWidget);
  });

  testWidgets('a silent ring reads as lost and reconnects on tap', (
    tester,
  ) async {
    final rig = WorkoutRig();
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await startRunning(tester, rig, seconds: 10);
    rig.run(heartRateLostAfter.inSeconds, bpm: null);
    await settle(tester);

    expect(find.text('Heart rate lost'), findsOneWidget);
    expect(
      find.text(
        'The ring has sent no heart rate for a while. That gap stays empty, '
        'and the workout keeps recording.',
      ),
      findsOneWidget,
    );
    expect(_text(tester, LiveWorkoutKeys.clock), '00:\u200B00:41');
    expect(_state(tester).status, WorkoutStatus.running);

    await _tap(tester, LiveWorkoutKeys.reconnect);
    await flushStreams(tester);
    expect(rig.heartRate.listens, 2);
    expect(rig.heartRate.cancels, 1);
    expect(find.text('Waiting for the ring'), findsOneWidget);
    expect(find.byKey(LiveWorkoutKeys.reconnect), findsNothing);

    rig.run(3);
    await settle(tester);
    expect(find.text('Ring sending heart rate every second'), findsOneWidget);
    expect(_state(tester).snapshot!.heartRateSamples, 13);
  });

  testWidgets('one reading then silence never reads as waiting again', (
    tester,
  ) async {
    final rig = WorkoutRig();
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await workoutOf(tester).start(WorkoutType.strength, notice: testNotice);
    rig.run(20, bpm: null);
    await settle(tester);
    expect(find.text('Waiting for the ring'), findsOneWidget);

    rig.second(bpm: 80);
    for (var quiet = 1; quiet < heartRateLostAfter.inSeconds; quiet++) {
      rig.second();
      await tester.pump();
      expect(find.text('Waiting for the ring'), findsNothing, reason: '$quiet');
      expect(find.text('Waiting for heart rate'), findsNothing);
      expect(find.text('80'), findsNWidgets(3), reason: 'current, avg, max');
    }

    rig.second();
    await settle(tester);
    expect(find.text('Heart rate lost'), findsOneWidget);
    expect(find.text('80'), findsNWidgets(2), reason: 'avg and max');
    expect(find.byKey(LiveWorkoutKeys.reconnect), findsOneWidget);
  });

  testWidgets('no paired ring is named in the link line', (tester) async {
    final rig = WorkoutRig();
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await workoutOf(tester).start(WorkoutType.running, notice: testNotice);
    rig.heartRate.fail(const HeartRateUnavailable(HeartRateProblem.noRing));
    await settle(tester);

    expect(find.text('No ring paired'), findsOneWidget);
    expect(find.byKey(LiveWorkoutKeys.reconnect), findsNothing);
  });

  testWidgets('a failed GPS reads as lost and tries again on tap', (
    tester,
  ) async {
    final rig = WorkoutRig();
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await startRunning(tester, rig, seconds: 10);
    rig.location.fail(StateError('gps crashed'));
    rig.run(5, meters: null);
    await settle(tester);

    expect(find.byKey(LiveWorkoutKeys.map), findsNothing);
    expect(find.text('GPS signal lost'), findsOneWidget);
    expect(
      find.text(
        "The phone's GPS stopped working. Time and heart rate still record.",
      ),
      findsOneWidget,
    );
    expect(find.byKey(LiveWorkoutKeys.settings), findsNothing);
    expect(find.text('Ring sending heart rate every second'), findsOneWidget);

    await _tap(tester, LiveWorkoutKeys.gpsRetry);
    await flushStreams(tester);
    expect(rig.location.listens, 2);
    expect(find.byKey(LiveWorkoutKeys.gpsProblem), findsNothing);
    expect(find.byKey(LiveWorkoutKeys.map), findsOneWidget);

    rig.run(3);
    await settle(tester);
    expect(find.textContaining('GPS good'), findsOneWidget);
    expect(_state(tester).snapshot!.trackPoints, 14);
  });

  testWidgets('denied location replaces the map and opens settings', (
    tester,
  ) async {
    final rig = WorkoutRig();
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await workoutOf(tester).start(WorkoutType.walking, notice: testNotice);
    rig.location.fail(const LocationUnavailable(LocationProblem.deniedForever));
    rig.run(5, meters: null);
    await settle(tester);

    expect(find.byKey(LiveWorkoutKeys.map), findsNothing);
    expect(find.byKey(LiveWorkoutKeys.gpsProblem), findsOneWidget);
    expect(
      find.text(
        'Location is not allowed, so there is no route. Time and heart rate '
        'still record.',
      ),
      findsOneWidget,
    );
    await _tap(tester, LiveWorkoutKeys.settings);
    expect(rig.access.appSettings, 1);
  });

  testWidgets('location switched off opens the location settings', (
    tester,
  ) async {
    final rig = WorkoutRig();
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await workoutOf(tester).start(WorkoutType.hiking, notice: testNotice);
    rig.location.fail(
      const LocationUnavailable(LocationProblem.serviceDisabled),
    );
    await settle(tester);

    await _tap(tester, LiveWorkoutKeys.settings);
    expect(rig.access.locationSettings, 1);
  });

  testWidgets('an indoor workout has no map and no distance', (tester) async {
    final rig = WorkoutRig();
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await startRunning(tester, rig, type: WorkoutType.other, seconds: 20);
    await settle(tester);

    expect(find.byKey(LiveWorkoutKeys.map), findsNothing);
    expect(find.byKey(LiveWorkoutKeys.gps), findsNothing);
    expect(find.text('Distance'), findsNothing);
    expect(find.text('Energy'), findsOneWidget);
    expect(rig.location.listens, 0);
  });

  testWidgets('cycling shows speed instead of pace', (tester) async {
    final rig = WorkoutRig();
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await startRunning(tester, rig, type: WorkoutType.cycling, seconds: 40);
    await settle(tester);

    expect(find.text('Current speed'), findsOneWidget);
    expect(find.text('Average speed'), findsOneWidget);
    expect(find.text('km/h'), findsNWidgets(2));
    expect(find.text('Current pace'), findsNothing);
  });

  testWidgets('without a profile there are no zones and no energy', (
    tester,
  ) async {
    final rig = WorkoutRig(profile: null);
    await pumpWorkout(tester, const LiveWorkoutScreen(), rig, size: tallPhone);
    await startRunning(tester, rig, seconds: 20);
    await settle(tester);

    expect(_text(tester, LiveWorkoutKeys.zoneCaption), 'Below zone 1');
    expect(
      find.text(
        'Add your birth year or max heart rate in Profile to see zones.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('German copy fits the live screen', (tester) async {
    final rig = WorkoutRig();
    await pumpWorkout(
      tester,
      const LiveWorkoutScreen(),
      rig,
      size: tallPhone,
      c: const LayoutCase(
        scale: 2,
        brightness: Brightness.light,
        locale: Locale('de'),
      ),
    );
    await startRunning(tester, rig);
    await settle(tester);

    expect(find.text('Laufen'), findsOneWidget);
    expect(find.text('Durchschnittliche Pace'), findsOneWidget);
  });
}
