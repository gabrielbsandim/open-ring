import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/workout/domain/live_heart_rate_source.dart';
import 'package:open_ring/features/workout/domain/location_access.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/live_workout_screen.dart';
import 'package:open_ring/features/workout/presentation/location_permission_screen.dart';
import 'package:open_ring/features/workout/presentation/workout_pick_screen.dart';
import 'package:open_ring/features/workout/presentation/workout_summary_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/workout_fakes.dart';
import 'workout_scenarios.dart';

typedef Drive = Future<void> Function(WidgetTester tester, WorkoutRig rig);

final class LayoutScenario {
  const new(
    this.screen, {
    this.drive,
    this.rig,
    this.ring = pairedRing,
    this.expected,
  });

  final Widget screen;
  final Drive? drive;
  final WorkoutRig Function()? rig;
  final RingStatus ring;
  final Key? expected;
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

WorkoutRig _savedRig({WorkoutType type = WorkoutType.running}) => WorkoutRig(
  store: MemoryWorkoutHistory(seed: [savedRun(type: type)]),
);

Future<void> _running(WidgetTester tester, WorkoutRig rig) =>
    startRunning(tester, rig);

Future<void> _finished(WidgetTester tester, WorkoutRig rig) async {
  await startRunning(tester, rig, seconds: 400);
  await finishWorkout(tester);
}

final scenarios = <String, LayoutScenario>{
  'Pick': const LayoutScenario(
    WorkoutPickScreen(),
    expected: WorkoutPickKeys.start,
  ),
  'Pick shows swimming as unavailable': const LayoutScenario(
    WorkoutPickScreen(),
    expected: WorkoutPickKeys.swimming,
  ),
  'Pick without a ring': const LayoutScenario(
    WorkoutPickScreen(initialType: WorkoutType.other),
    ring: RingStatus.unpaired,
    expected: WorkoutPickKeys.ring,
  ),
  'Pick other with GPS on': LayoutScenario(
    const WorkoutPickScreen(initialType: WorkoutType.other),
    drive: (tester, rig) => _tapKey(tester, WorkoutPickKeys.gps),
    expected: WorkoutPickKeys.gps,
  ),
  'Pick an indoor type': const LayoutScenario(
    WorkoutPickScreen(initialType: WorkoutType.stationaryBike),
    expected: WorkoutPickKeys.detail,
  ),
  'Location before asking': const LayoutScenario(
    LocationPermissionScreen(type: WorkoutType.running),
    expected: LocationPermissionKeys.allow,
  ),
  for (final status in LocationAccessStatus.values)
    'Location ${status.name}': LayoutScenario(
      LocationPermissionScreen(
        type: WorkoutType.running,
        initialStatus: status,
      ),
      expected: LocationPermissionKeys.outcome,
    ),
  'Live without a workout': const LayoutScenario(
    LiveWorkoutScreen(),
    expected: LiveWorkoutKeys.none,
  ),
  'Live running': const LayoutScenario(
    LiveWorkoutScreen(),
    drive: _running,
    expected: LiveWorkoutKeys.toggle,
  ),
  'Live paused': LayoutScenario(
    const LiveWorkoutScreen(),
    drive: (tester, rig) async {
      await startRunning(tester, rig);
      workoutOf(tester).pause();
    },
    expected: LiveWorkoutKeys.toggle,
  ),
  'Live confirm': const LayoutScenario(
    LiveWorkoutScreen(initialConfirming: true),
    drive: _running,
    expected: LiveWorkoutKeys.confirm,
  ),
  'Live saved': const LayoutScenario(
    LiveWorkoutScreen(),
    drive: _finished,
    expected: LiveWorkoutKeys.saved,
  ),
  'Live save failed': LayoutScenario(
    const LiveWorkoutScreen(),
    rig: () => WorkoutRig(store: FlakyWorkoutStore(RecordingWorkoutStore())),
    drive: _finished,
    expected: LiveWorkoutKeys.failed,
  ),
  'Live discarded': LayoutScenario(
    const LiveWorkoutScreen(),
    drive: (tester, rig) async {
      await startRunning(tester, rig);
      await discardWorkout(tester);
    },
    expected: LiveWorkoutKeys.discarded,
  ),
  'Live without a GPS fix': LayoutScenario(
    const LiveWorkoutScreen(),
    drive: (tester, rig) async {
      await workoutOf(tester).start(WorkoutType.running, notice: testNotice);
      rig.run(20, meters: null);
    },
    expected: LiveWorkoutKeys.gps,
  ),
  'Live with the ring disconnected': LayoutScenario(
    const LiveWorkoutScreen(),
    drive: (tester, rig) async {
      await startRunning(tester, rig);
      rig.heartRate.fail(
        const HeartRateUnavailable(HeartRateProblem.unreachable),
      );
      rig.run(15, bpm: null);
    },
    expected: LiveWorkoutKeys.heart,
  ),
  'Live with location denied': LayoutScenario(
    const LiveWorkoutScreen(),
    drive: (tester, rig) async {
      await workoutOf(tester).start(WorkoutType.walking, notice: testNotice);
      rig.location.fail(const LocationUnavailable(LocationProblem.denied));
      rig.run(30, meters: null);
    },
    expected: LiveWorkoutKeys.gpsProblem,
  ),
  'Live indoor without a profile': LayoutScenario(
    const LiveWorkoutScreen(),
    rig: () => WorkoutRig(profile: null),
    drive: (tester, rig) =>
        startRunning(tester, rig, type: WorkoutType.other, seconds: 60),
    expected: LiveWorkoutKeys.metrics,
  ),
  'Summary without a workout': const LayoutScenario(
    WorkoutSummaryScreen(),
    expected: WorkoutSummaryKeys.none,
  ),
  'Summary after a run': const LayoutScenario(
    WorkoutSummaryScreen(),
    drive: _finished,
    expected: WorkoutSummaryKeys.zones,
  ),
  'Saved summary splits': const LayoutScenario(
    WorkoutSummaryScreen(workoutId: savedRunId),
    rig: _savedRig,
    expected: WorkoutSummaryKeys.splits,
  ),
  'Saved summary pauses and actions': const LayoutScenario(
    WorkoutSummaryScreen(workoutId: savedRunId),
    rig: _savedRig,
    expected: WorkoutSummaryKeys.delete,
  ),
  'Saved summary export buttons': const LayoutScenario(
    WorkoutSummaryScreen(workoutId: savedRunId),
    rig: _savedRig,
    expected: WorkoutSummaryKeys.exportCsv,
  ),
  'Saved summary confirming delete': LayoutScenario(
    const WorkoutSummaryScreen(workoutId: savedRunId),
    rig: _savedRig,
    drive: (tester, rig) => _tapKey(tester, WorkoutSummaryKeys.delete),
    expected: WorkoutSummaryKeys.deleteConfirm,
  ),
  'Saved summary deleted': LayoutScenario(
    const WorkoutSummaryScreen(workoutId: savedRunId),
    rig: _savedRig,
    drive: (tester, rig) async {
      await _tapKey(tester, WorkoutSummaryKeys.delete);
      await _tapKey(tester, WorkoutSummaryKeys.deleteConfirm);
    },
    expected: WorkoutSummaryKeys.deleted,
  ),
  'Saved indoor summary': LayoutScenario(
    const WorkoutSummaryScreen(workoutId: savedRunId),
    rig: () => _savedRig(type: WorkoutType.yoga),
    expected: WorkoutSummaryKeys.pauses,
  ),
  'Summary of a missing workout': const LayoutScenario(
    WorkoutSummaryScreen(workoutId: 99),
    expected: WorkoutSummaryKeys.none,
  ),
  'Summary of a cycling ride without a route': LayoutScenario(
    const WorkoutSummaryScreen(),
    drive: (tester, rig) async {
      await workoutOf(tester).start(WorkoutType.cycling, notice: testNotice);
      rig.run(120, meters: null);
      await finishWorkout(tester);
    },
    expected: WorkoutSummaryKeys.noRoute,
  ),
};

void main() {
  for (final MapEntry(key: name, value: scenario) in scenarios.entries) {
    group(name, () {
      for (final c in layoutMatrix()) {
        testWidgets('lays out without overflow at $c', (tester) async {
          final rig = scenario.rig?.call() ?? WorkoutRig();
          await pumpWorkout(
            tester,
            scenario.screen,
            rig,
            c: c,
            ring: scenario.ring,
          );
          await scenario.drive?.call(tester, rig);
          await settle(tester);

          expect(find.byWidget(scenario.screen), findsOneWidget);
          final expected = scenario.expected;
          if (expected == null) return;
          await tester.scrollUntilVisible(
            find.byKey(expected),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.byKey(expected), findsOneWidget);
        });
      }
    });
  }
}
