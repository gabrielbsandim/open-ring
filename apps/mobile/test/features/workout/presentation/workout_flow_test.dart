import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/domain/location_access.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/live_workout_screen.dart';
import 'package:open_ring/features/workout/presentation/location_permission_screen.dart';
import 'package:open_ring/features/workout/presentation/recent_workouts_card.dart';
import 'package:open_ring/features/workout/presentation/workout_entry_button.dart';
import 'package:open_ring/features/workout/presentation/workout_pick_screen.dart';
import 'package:open_ring/features/workout/presentation/workout_summary_screen.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/workout_fakes.dart';
import 'workout_scenarios.dart';

Future<void> _pumpApp(WidgetTester tester, WorkoutRig rig) async {
  await pumpScaled(
    tester,
    const OpenRingApp(),
    textScaler: TextScaler.noScaling,
    brightness: Brightness.dark,
    locale: const Locale('en'),
    size: tallPhone,
    overrides: [
      ...bleOverrides(),
      ...ringOverrides(),
      ...rig.overrides(),
      ringStatusReaderProvider.overrideWithValue(
        FakeRingStatusReader(pairedRing),
      ),
    ],
  );
  await tester.tap(
    find.byKey(AppNavigationBar.destinationKey(AppTab.activity)),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

WorkoutStatus _status(WidgetTester tester) =>
    workoutContainer(tester).read(workoutProvider).status;

void main() {
  testWidgets('Activity starts an indoor workout without asking for location', (
    tester,
  ) async {
    final rig = WorkoutRig(access: LocationAccessStatus.denied);
    await _pumpApp(tester, rig);

    await _tap(tester, find.byKey(WorkoutEntryButton.startKey));
    expect(find.byType(WorkoutPickScreen), findsOneWidget);
    expect(find.text('Ring paired · battery 68%'), findsOneWidget);

    await _tap(tester, find.byKey(WorkoutPickKeys.type(WorkoutType.other)));
    expect(find.text('Other · what is recorded'), findsOneWidget);
    await _tap(tester, find.byKey(WorkoutPickKeys.start));

    expect(find.byType(LiveWorkoutScreen), findsOneWidget);
    expect(_status(tester), WorkoutStatus.running);
    expect(rig.access.requests, 0);
    expect(rig.location.listens, 0);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(WorkoutEntryButton.liveKey), findsOneWidget);
    await _tap(tester, find.byKey(WorkoutEntryButton.liveKey));
    expect(find.byType(LiveWorkoutScreen), findsOneWidget);
  });

  testWidgets('swimming is shown as unavailable and offers no action', (
    tester,
  ) async {
    await pumpWorkout(
      tester,
      const WorkoutPickScreen(),
      WorkoutRig(),
      size: tallPhone,
    );

    expect(find.text('Swimming · unavailable'), findsOneWidget);
    final row = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(WorkoutPickKeys.swimming),
        matching: find.byType(InkWell),
      ),
    );
    expect(row.onTap, isNull);
    expect(
      WorkoutType.values.map((type) => type.name),
      isNot(contains('swimming')),
    );
  });

  testWidgets('an outdoor workout explains location, asks, then starts', (
    tester,
  ) async {
    final rig = WorkoutRig(access: LocationAccessStatus.denied);
    await _pumpApp(tester, rig);

    await _tap(tester, find.byKey(WorkoutEntryButton.startKey));
    await _tap(tester, find.byKey(WorkoutPickKeys.start));
    expect(find.byType(LocationPermissionScreen), findsOneWidget);
    expect(find.text('Record the workout route'), findsOneWidget);
    expect(_status(tester), WorkoutStatus.idle);

    await _tap(tester, find.byKey(LocationPermissionKeys.allow));
    expect(rig.access.requests, 1);
    expect(find.text('Location allowed'), findsOneWidget);

    await _tap(tester, find.byKey(LocationPermissionKeys.start));
    expect(find.byType(LiveWorkoutScreen), findsOneWidget);
    expect(_status(tester), WorkoutStatus.running);
    expect(rig.location.listens, 1);
    expect(rig.location.notice?.title, 'OpenRing workout');
    expect(rig.location.notice?.text, 'Recording your route');
    expect(rig.location.notice?.channel, 'Workout');
  });

  testWidgets('granted location skips the explainer', (tester) async {
    final rig = WorkoutRig();
    await _pumpApp(tester, rig);

    await _tap(tester, find.byKey(WorkoutEntryButton.startKey));
    await _tap(tester, find.byKey(WorkoutPickKeys.type(WorkoutType.cycling)));
    await _tap(tester, find.byKey(WorkoutPickKeys.start));

    expect(find.byType(LocationPermissionScreen), findsNothing);
    expect(find.byType(LiveWorkoutScreen), findsOneWidget);
    expect(find.text('Cycling'), findsOneWidget);
    expect(rig.location.notice?.title, 'OpenRing workout');
  });

  testWidgets('denied location can still train without GPS', (tester) async {
    final rig = WorkoutRig(access: LocationAccessStatus.denied);
    rig.access.afterRequest = LocationAccessStatus.deniedForever;
    await _pumpApp(tester, rig);

    await _tap(tester, find.byKey(WorkoutEntryButton.startKey));
    await _tap(tester, find.byKey(WorkoutPickKeys.start));
    await _tap(tester, find.byKey(LocationPermissionKeys.allow));
    expect(find.text('Location is blocked for OpenRing'), findsOneWidget);

    await _tap(tester, find.byKey(LocationPermissionKeys.settings));
    expect(rig.access.appSettings, 1);

    await _tap(tester, find.byKey(LocationPermissionKeys.withoutGps));
    expect(find.byType(LiveWorkoutScreen), findsOneWidget);
    expect(_status(tester), WorkoutStatus.running);
  });

  testWidgets('a saved workout opens its summary', (tester) async {
    final rig = WorkoutRig();
    await _pumpApp(tester, rig);
    await _tap(tester, find.byKey(WorkoutEntryButton.startKey));
    await _tap(tester, find.byKey(WorkoutPickKeys.start));
    rig
      ..second(meters: 0)
      ..run(300);
    await tester.pumpAndSettle();

    await _tap(tester, find.byKey(LiveWorkoutKeys.end));
    await _tap(tester, find.byKey(LiveWorkoutKeys.save));
    await flushStreams(tester);
    await _tap(tester, find.byKey(LiveWorkoutKeys.summary));

    expect(find.byType(WorkoutSummaryScreen), findsOneWidget);
    expect(find.byKey(WorkoutSummaryKeys.route), findsOneWidget);
    expect(find.text('00:05:01'), findsOneWidget);

    await _tap(tester, find.byKey(WorkoutSummaryKeys.back));
    expect(find.byKey(WorkoutEntryButton.startKey), findsOneWidget);
  });

  testWidgets('an outdoor workout with GPS turned off never asks', (
    tester,
  ) async {
    final rig = WorkoutRig(access: LocationAccessStatus.denied);
    await _pumpApp(tester, rig);

    await _tap(tester, find.byKey(WorkoutEntryButton.startKey));
    await _tap(tester, find.byKey(WorkoutPickKeys.gps));
    await _tap(tester, find.byKey(WorkoutPickKeys.start));

    expect(find.byType(LiveWorkoutScreen), findsOneWidget);
    expect(find.byKey(LiveWorkoutKeys.gps), findsNothing);
    expect(rig.access.requests, 0);
    expect(rig.location.listens, 0);
    expect(workoutContainer(tester).read(workoutProvider).snapshot?.gps, false);
  });

  testWidgets('a saved workout is listed on Activity, opens and deletes', (
    tester,
  ) async {
    final history = MemoryWorkoutHistory();
    final rig = WorkoutRig(store: history);
    await _pumpApp(tester, rig);
    expect(find.byKey(RecentWorkoutsKeys.empty), findsOneWidget);

    await _tap(tester, find.byKey(WorkoutEntryButton.startKey));
    await _tap(tester, find.byKey(WorkoutPickKeys.start));
    rig
      ..second(meters: 0)
      ..run(400);
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(LiveWorkoutKeys.end));
    await _tap(tester, find.byKey(LiveWorkoutKeys.save));
    await flushStreams(tester);
    await _tap(tester, find.byKey(LiveWorkoutKeys.summary));
    await _tap(tester, find.byKey(WorkoutSummaryKeys.back));

    final item = find.byKey(RecentWorkoutsKeys.item(1));
    await _tap(tester, item);
    expect(find.byType(WorkoutSummaryScreen), findsOneWidget);
    expect(find.byKey(WorkoutSummaryKeys.route), findsOneWidget);
    expect(find.text('00:06:41'), findsOneWidget);

    await _tap(tester, find.byKey(WorkoutSummaryKeys.delete));
    await _tap(tester, find.byKey(WorkoutSummaryKeys.deleteConfirm));
    expect(find.byKey(WorkoutSummaryKeys.deleted), findsOneWidget);
    expect(_status(tester), WorkoutStatus.idle);
    await _tap(tester, find.byKey(WorkoutSummaryKeys.back));

    expect(find.byKey(RecentWorkoutsKeys.empty), findsOneWidget);
    expect(await history.recent(limit: 5), isEmpty);
  });
}
