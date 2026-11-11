import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/domain/location_access.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/workout_pick_screen.dart';
import 'package:open_ring/features/workout/presentation/workout_summary_screen.dart';

import '../../../helpers/workout_fakes.dart';
import 'workout_scenarios.dart';

Future<void> _reveal(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await _reveal(tester, key);
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<MemoryWorkoutHistory> _pumpSaved(
  WidgetTester tester, {
  int id = savedRunId,
  WorkoutHealthStatus health = WorkoutHealthStatus.sent,
}) async {
  final history = MemoryWorkoutHistory(seed: [savedRun(health: health)]);
  final rig = WorkoutRig(store: history);
  await pumpWorkout(
    tester,
    WorkoutSummaryScreen(workoutId: id),
    rig,
    size: tallPhone,
  );
  await tester.pumpAndSettle();
  return history;
}

void main() {
  testWidgets('a saved workout shows splits, climb, zones and pauses', (
    tester,
  ) async {
    await _pumpSaved(tester);

    expect(find.text('Running'), findsOneWidget);
    expect(find.byKey(WorkoutSummaryKeys.route), findsOneWidget);
    expect(find.text('1.80'), findsOneWidget);
    await _reveal(tester, WorkoutSummaryKeys.climb);
    expect(find.text('Climb'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    await _reveal(tester, WorkoutSummaryKeys.splits);
    expect(find.byKey(WorkoutSummaryKeys.split(1)), findsOneWidget);
    expect(find.byKey(WorkoutSummaryKeys.split(2)), findsOneWidget);
    expect(find.text('Km 1'), findsOneWidget);
    expect(find.text('Km 1.80'), findsOneWidget);
    expect(find.textContaining('The last split is 0.80 km'), findsOneWidget);
    await _reveal(tester, WorkoutSummaryKeys.zones);
    await _reveal(tester, WorkoutSummaryKeys.pauses);
    expect(find.text('1 pause · 1 min paused'), findsOneWidget);
    await _reveal(tester, WorkoutSummaryKeys.status);
    expect(find.text('In Health Connect'), findsOneWidget);
    expect(
      find.textContaining('Exercise session with a route and'),
      findsOneWidget,
    );
  });

  testWidgets('the picker marks the type of the last workout', (tester) async {
    await pumpWorkout(
      tester,
      const WorkoutPickScreen(),
      WorkoutRig(
        store: MemoryWorkoutHistory(
          seed: [savedRun(type: WorkoutType.values.last)],
        ),
      ),
      size: tallPhone,
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(WorkoutPickKeys.type(WorkoutType.values.last)),
        matching: find.text('last'),
      ),
      findsOneWidget,
    );
    expect(find.text('last'), findsOneWidget);
  });

  testWidgets('a pending workout says it waits for Health', (tester) async {
    await _pumpSaved(tester, health: WorkoutHealthStatus.pending);

    await _reveal(tester, WorkoutSummaryKeys.status);
    expect(find.text('Waiting for Health Connect'), findsOneWidget);
  });

  testWidgets('an unknown id says the workout is gone', (tester) async {
    await _pumpSaved(tester, id: 99);

    expect(find.byKey(WorkoutSummaryKeys.none), findsOneWidget);
    expect(
      find.text('This workout is no longer on this phone.'),
      findsOneWidget,
    );
  });

  testWidgets('export shares a GPX with a segment per pause and HR', (
    tester,
  ) async {
    final history = MemoryWorkoutHistory(seed: [savedRun()]);
    final rig = WorkoutRig(store: history);
    await pumpWorkout(
      tester,
      const WorkoutSummaryScreen(workoutId: savedRunId),
      rig,
      size: tallPhone,
    );

    await _tap(tester, WorkoutSummaryKeys.exportGpx);

    final route = rig.exporter.routes.single;
    expect(route.segments, hasLength(2));
    expect(route.activityType, 'running');
    expect(route.points.every((p) => p.heartRateBpm != null), isTrue);
    final (files, subject) = rig.sharer.shared.single;
    expect(files.single.mimeType, 'application/gpx+xml');
    expect(subject, 'openring-route-20261110-073000.gpx');
    expect(find.byKey(WorkoutSummaryKeys.exportFailed), findsNothing);
  });

  testWidgets('a saved workout exports its series as CSV', (tester) async {
    final rig = WorkoutRig(store: MemoryWorkoutHistory(seed: [savedRun()]));
    await pumpWorkout(
      tester,
      const WorkoutSummaryScreen(workoutId: savedRunId),
      rig,
      size: tallPhone,
    );

    await _tap(tester, WorkoutSummaryKeys.exportCsv);

    final (workout, _) = rig.exporter.csvExports.single;
    expect(workout.heartRate, isNotEmpty);
    expect(rig.exporter.routes, isEmpty);
    final (files, subject) = rig.sharer.shared.single;
    expect(files.single.mimeType, 'text/csv');
    expect(subject, 'openring-workout-20261110-073000.csv');
    expect(find.byKey(WorkoutSummaryKeys.exportFailed), findsNothing);
  });

  testWidgets('a workout with nothing recorded offers no export', (
    tester,
  ) async {
    final empty = FinishedWorkout(
      type: WorkoutType.running,
      start: workoutStart,
      end: workoutStart.add(const Duration(minutes: 1)),
      elapsed: const Duration(minutes: 1),
      heartRate: const [],
      route: WorkoutRoute(segments: const []),
      pauses: const [],
    );
    final saved = savedRun();
    final rig = WorkoutRig(
      store: MemoryWorkoutHistory(
        seed: [
          SavedWorkout(
            id: saved.id,
            workout: empty,
            utcOffset: saved.utcOffset,
            health: saved.health,
          ),
        ],
      ),
    );
    await pumpWorkout(
      tester,
      const WorkoutSummaryScreen(workoutId: savedRunId),
      rig,
      size: tallPhone,
    );

    await _reveal(tester, WorkoutSummaryKeys.delete);
    expect(find.byKey(WorkoutSummaryKeys.exportCsv), findsNothing);
    expect(find.byKey(WorkoutSummaryKeys.exportGpx), findsNothing);
  });

  testWidgets('a failed export says so and can be retried', (tester) async {
    final rig = WorkoutRig(store: MemoryWorkoutHistory(seed: [savedRun()]));
    rig.sharer.fail = true;
    await pumpWorkout(
      tester,
      const WorkoutSummaryScreen(workoutId: savedRunId),
      rig,
      size: tallPhone,
    );

    await _tap(tester, WorkoutSummaryKeys.exportGpx);
    expect(find.byKey(WorkoutSummaryKeys.exportFailed), findsOneWidget);

    rig.sharer.fail = false;
    await _tap(tester, WorkoutSummaryKeys.exportGpx);
    expect(find.byKey(WorkoutSummaryKeys.exportFailed), findsNothing);
    expect(rig.sharer.shared, hasLength(1));
  });

  testWidgets('delete asks first, then removes the workout', (tester) async {
    final history = await _pumpSaved(tester);

    await _tap(tester, WorkoutSummaryKeys.delete);
    expect(find.text('Delete this workout?'), findsOneWidget);
    expect(
      find.textContaining('A copy already sent to Health Connect stays there'),
      findsOneWidget,
    );
    await _tap(tester, WorkoutSummaryKeys.deleteCancel);
    expect(find.text('Delete this workout?'), findsNothing);
    expect(await history.byId(savedRunId), isNotNull);

    await _tap(tester, WorkoutSummaryKeys.delete);
    await _tap(tester, WorkoutSummaryKeys.deleteConfirm);

    expect(await history.byId(savedRunId), isNull);
    expect(find.byKey(WorkoutSummaryKeys.deleted), findsOneWidget);
    expect(find.text('Workout deleted'), findsOneWidget);
    expect(find.byKey(WorkoutSummaryKeys.back), findsOneWidget);
  });

  testWidgets('a failed delete keeps the workout and says so', (tester) async {
    final history = await _pumpSaved(tester);
    history.failDelete = true;

    await _tap(tester, WorkoutSummaryKeys.delete);
    await _tap(tester, WorkoutSummaryKeys.deleteConfirm);

    expect(find.byKey(WorkoutSummaryKeys.deleteFailed), findsOneWidget);
    expect(find.byKey(WorkoutSummaryKeys.deleted), findsNothing);
  });

  testWidgets('an indoor workout has no route, splits or export', (
    tester,
  ) async {
    final rig = WorkoutRig(
      store: MemoryWorkoutHistory(seed: [savedRun(type: WorkoutType.yoga)]),
    );
    await pumpWorkout(
      tester,
      const WorkoutSummaryScreen(workoutId: savedRunId),
      rig,
      size: tallPhone,
    );

    expect(find.text('Yoga'), findsOneWidget);
    await _reveal(tester, WorkoutSummaryKeys.delete);
    expect(find.byKey(WorkoutSummaryKeys.route), findsNothing);
    expect(find.byKey(WorkoutSummaryKeys.splits), findsNothing);
    expect(find.byKey(WorkoutSummaryKeys.exportCsv), findsOneWidget);
    expect(find.byKey(WorkoutSummaryKeys.exportGpx), findsNothing);
  });

  testWidgets('the last workout provider follows saves and deletes', (
    tester,
  ) async {
    final history = MemoryWorkoutHistory(
      seed: [
        savedRun(id: 1),
        savedRun(id: 2, startAfter: const Duration(days: 1)),
      ],
    );
    final rig = WorkoutRig(store: history);
    await pumpWorkout(tester, const WorkoutPickScreen(), rig);
    final container = workoutContainer(tester);

    Future<int?> lastId() async =>
        switch (await container.read(lastWorkoutProvider.future)) {
          WorkoutListItem(:final id) => id,
          _ => null,
        };

    expect(await lastId(), 2);
    await history.delete(2);
    container.read(dataRevisionProvider.notifier).bump();
    expect(await lastId(), 1);
  });

  group('GPS choice on the pick screen', () {
    testWidgets('an outdoor type can start without GPS or asking', (
      tester,
    ) async {
      final rig = WorkoutRig(access: LocationAccessStatus.denied);
      await pumpWorkout(
        tester,
        const WorkoutPickScreen(),
        rig,
        size: tallPhone,
      );

      expect(
        tester.widget<SwitchListTile>(find.byKey(WorkoutPickKeys.gps)).value,
        isTrue,
      );
      await _tap(tester, WorkoutPickKeys.gps);
      expect(
        find.text('Without GPS this workout has no route or distance.'),
        findsOneWidget,
      );
    });

    testWidgets('an indoor type shows no switch', (tester) async {
      await pumpWorkout(
        tester,
        const WorkoutPickScreen(initialType: WorkoutType.strength),
        WorkoutRig(),
        size: tallPhone,
      );

      expect(find.byKey(WorkoutPickKeys.gps), findsNothing);
      expect(
        find.text('Indoor workout, so GPS stays off to save battery.'),
        findsOneWidget,
      );
    });

    testWidgets('other starts with GPS off and can turn it on', (tester) async {
      await pumpWorkout(
        tester,
        const WorkoutPickScreen(initialType: WorkoutType.other),
        WorkoutRig(),
        size: tallPhone,
      );

      expect(
        tester.widget<SwitchListTile>(find.byKey(WorkoutPickKeys.gps)).value,
        isFalse,
      );
      await _tap(tester, WorkoutPickKeys.gps);
      expect(
        tester.widget<SwitchListTile>(find.byKey(WorkoutPickKeys.gps)).value,
        isTrue,
      );
    });
  });
}
