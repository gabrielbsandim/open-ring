import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/activity/presentation/activity_screen.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/imported_workout_screen.dart';
import 'package:open_ring/features/workout/presentation/recent_workouts_card.dart';
import 'package:open_ring/features/workout/presentation/workout_summary_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/workout_fakes.dart';
import 'workout_scenarios.dart';

const _watch = 'com.garmin.android.apps.connectmobile';
const _fit = 'com.google.android.apps.fitness';

final class _FixedImportedWorkouts implements ImportedWorkoutReader {
  const new(this.workouts);

  final List<ImportedWorkout> workouts;

  @override
  Future<ImportedWorkouts> recent({required int limit}) async => (
    priority: const [ringSource, _watch, _fit],
    workouts: workouts.take(limit).toList(),
  );

  @override
  Future<ImportedWorkout?> byRecordId(String recordId) async {
    for (final workout in workouts) {
      if (workout.recordId == recordId) return workout;
    }
    return null;
  }
}

ImportedWorkout _imported(
  String id,
  String source,
  DateTime start, {
  WorkoutType type = WorkoutType.cycling,
}) => ImportedWorkout(
  recordId: id,
  source: source,
  type: type,
  start: start,
  end: start.add(const Duration(minutes: 45)),
  utcOffset: Duration.zero,
);

// A Garmin ride yesterday, and Google Fit's copy of OpenRing's run today,
// which the run outranks.
final List<ImportedWorkout> _workouts = [
  _imported('ride', _watch, workoutStart.subtract(const Duration(days: 1))),
  _imported(
    'copy',
    _fit,
    workoutStart.add(const Duration(minutes: 2)),
    type: WorkoutType.running,
  ),
];

List<Override> _overrides() => [
  ...metricsOverrides(fullDataScenario),
  workoutHistoryReaderProvider.overrideWithValue(
    MemoryWorkoutHistory(seed: [savedRun(id: 1)]),
  ),
  importedWorkoutReaderProvider.overrideWithValue(
    _FixedImportedWorkouts(_workouts),
  ),
];

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('recent workouts list imported ones with their app', (
    tester,
  ) async {
    await pumpScaled(
      tester,
      screenHost(const ActivityScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: _overrides(),
    );

    final ride = find.byKey(RecentWorkoutsKeys.importedItem('ride'));
    await _reveal(tester, ride);
    expect(find.byKey(RecentWorkoutsKeys.item(1)), findsOneWidget);
    expect(
      find.descendant(of: ride, matching: find.text('From Garmin Connect')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: ride, matching: find.text('Yesterday · 45 min')),
      findsOneWidget,
    );
    expect(find.byKey(RecentWorkoutsKeys.importedItem('copy')), findsNothing);
    expect(find.text('From Google Fit'), findsNothing);
  });

  testWidgets('an imported workout opens a read only summary', (tester) async {
    await pumpScaled(
      tester,
      const OpenRingApp(),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      size: tallPhone,
      overrides: _overrides(),
    );
    await tester.tap(
      find.byKey(AppNavigationBar.destinationKey(AppTab.activity)),
    );
    await tester.pumpAndSettle();

    final ride = find.byKey(RecentWorkoutsKeys.importedItem('ride'));
    await _reveal(tester, ride);
    await tester.tap(ride);
    await tester.pumpAndSettle();

    expect(find.byType(ImportedWorkoutScreen), findsOneWidget);
    expect(find.text('Cycling'), findsOneWidget);
    expect(find.text('00:45:00'), findsOneWidget);
    expect(find.text('From Garmin Connect'), findsOneWidget);
    expect(
      find.textContaining('to change or delete it, use Garmin Connect'),
      findsOneWidget,
    );
    expect(find.byKey(WorkoutSummaryKeys.delete), findsNothing);
    expect(find.byKey(WorkoutSummaryKeys.exportGpx), findsNothing);

    await _reveal(tester, find.byKey(ImportedWorkoutKeys.back));
    await tester.tap(find.byKey(ImportedWorkoutKeys.back));
    await tester.pumpAndSettle();
    expect(find.byType(ActivityScreen), findsOneWidget);
  });

  testWidgets('an imported workout no longer stored says it is gone', (
    tester,
  ) async {
    await pumpScaled(
      tester,
      screenHost(const ImportedWorkoutScreen(recordId: 'missing')),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.light,
      locale: const Locale('de'),
      overrides: _overrides(),
    );

    expect(find.byKey(ImportedWorkoutKeys.missing), findsOneWidget);
    expect(
      find.text('Dieses Training ist nicht mehr auf diesem Telefon.'),
      findsOneWidget,
    );
  });

  group('layout', () {
    for (final c in layoutMatrix()) {
      testWidgets('the imported summary lays out without overflow at $c', (
        tester,
      ) async {
        await pumpScaled(
          tester,
          screenHost(const ImportedWorkoutScreen(recordId: 'ride')),
          textScaler: c.textScaler,
          brightness: c.brightness,
          locale: c.locale,
          overrides: _overrides(),
        );

        expect(find.byKey(ImportedWorkoutKeys.source), findsOneWidget);
        await expectNoLayoutOverflow(
          () => _reveal(tester, find.byKey(ImportedWorkoutKeys.back)),
        );
      });

      testWidgets('an imported row lays out without overflow at $c', (
        tester,
      ) async {
        await pumpScaled(
          tester,
          screenHost(const ActivityScreen()),
          textScaler: c.textScaler,
          brightness: c.brightness,
          locale: c.locale,
          overrides: _overrides(),
        );

        await expectNoLayoutOverflow(
          () => _reveal(
            tester,
            find.byKey(RecentWorkoutsKeys.importedItem('ride')),
          ),
        );
      });
    }
  });
}
