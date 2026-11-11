import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/domain/workout_analysis.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/live_workout_screen.dart';
import 'package:open_ring/features/workout/presentation/workout_entry_button.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/features/workout/presentation/workout_pick_screen.dart';
import 'package:open_ring/features/workout/presentation/workout_summary_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/workout_fakes.dart';
import 'workout_scenarios.dart';

UnitFormat imperialIn(Locale locale) => UnitFormat(
  MetricFormat(lookupAppLocalizations(locale), locale.toString()),
  UnitSystem.imperial,
);

Finder inside(Key key, String text) =>
    find.descendant(of: find.byKey(key), matching: find.text(text));

Future<void> reveal(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await settle(tester);
}

void main() {
  for (final c in layoutMatrix()) {
    testWidgets('live running shows miles and pace per mile at $c', (
      tester,
    ) async {
      final rig = WorkoutRig(units: UnitSystem.imperial);
      await pumpWorkout(tester, const LiveWorkoutScreen(), rig, c: c);
      await startRunning(tester, rig);
      await settle(tester);

      final units = imperialIn(c.locale);
      final l10n = units.l10n;
      final snapshot = workoutContainer(tester).read(workoutProvider).snapshot!;
      await reveal(tester, LiveWorkoutKeys.metrics);

      const metrics = LiveWorkoutKeys.metrics;
      expect(
        inside(metrics, units.distance(snapshot.distanceMeters)),
        findsOneWidget,
      );
      expect(inside(metrics, l10n.workoutUnitMi), findsOneWidget);
      expect(inside(metrics, l10n.workoutUnitPaceMi), findsNWidgets(2));
      expect(find.text(l10n.workoutUnitKm), findsNothing);
      expect(find.text(l10n.workoutUnitPace), findsNothing);
    });

    testWidgets('a cycling ride shows mph at $c', (tester) async {
      final rig = WorkoutRig(units: UnitSystem.imperial);
      await pumpWorkout(tester, const LiveWorkoutScreen(), rig, c: c);
      await startRunning(tester, rig, type: WorkoutType.cycling);
      await settle(tester);
      await reveal(tester, LiveWorkoutKeys.metrics);

      final l10n = imperialIn(c.locale).l10n;
      expect(
        inside(LiveWorkoutKeys.metrics, l10n.workoutUnitSpeedMph),
        findsNWidgets(2),
      );
      expect(find.text(l10n.workoutUnitSpeed), findsNothing);
    });

    testWidgets('a saved run shows miles, feet and splits per mile at $c', (
      tester,
    ) async {
      final saved = savedRun();
      final rig = WorkoutRig(
        store: MemoryWorkoutHistory(seed: [saved]),
        units: UnitSystem.imperial,
      );
      await pumpWorkout(
        tester,
        const WorkoutSummaryScreen(workoutId: savedRunId),
        rig,
        c: c,
      );

      final units = imperialIn(c.locale);
      final l10n = units.l10n;
      final workout = saved.workout;
      final splits = units.splitsOf(workout);
      expect(splits.first.splitMeters, ImperialUnits.metersPerMile);
      expect(
        inside(
          WorkoutSummaryKeys.distance,
          units.distance(workout.distanceMeters),
        ),
        findsOneWidget,
      );
      expect(
        inside(WorkoutSummaryKeys.distance, l10n.workoutUnitMi),
        findsOneWidget,
      );

      await reveal(tester, WorkoutSummaryKeys.climb);
      final climb = elevationGainMeters(workout.route)!;
      expect(inside(WorkoutSummaryKeys.climb, units.length(climb)), findsOne);
      expect(inside(WorkoutSummaryKeys.climb, l10n.workoutUnitFeet), findsOne);
      expect(
        inside(WorkoutSummaryKeys.stats, l10n.workoutUnitPaceMi),
        findsOneWidget,
      );

      await reveal(tester, WorkoutSummaryKeys.splits);
      expect(inside(WorkoutSummaryKeys.splits, units.splitsTitle), findsOne);
      expect(
        inside(WorkoutSummaryKeys.splits, '${l10n.workoutSplitMi} 1'),
        findsOneWidget,
      );
      expect(
        inside(WorkoutSummaryKeys.splits, units.splitLastNote(splits.last)),
        findsOneWidget,
      );
      expect(find.text(l10n.workoutSplitsTitle), findsNothing);
    });
  }

  testWidgets('the imperial summary reads in English as the user expects', (
    tester,
  ) async {
    final rig = WorkoutRig(
      store: MemoryWorkoutHistory(seed: [savedRun()]),
      units: UnitSystem.imperial,
    );
    await pumpWorkout(
      tester,
      const WorkoutSummaryScreen(workoutId: savedRunId),
      rig,
      size: tallPhone,
    );

    expect(inside(WorkoutSummaryKeys.distance, '1.12'), findsOneWidget);
    expect(inside(WorkoutSummaryKeys.climb, '98'), findsOneWidget);
    expect(find.text('Splits per mile'), findsOneWidget);
    expect(find.text('Mile 1'), findsOneWidget);
    expect(find.text('Mile 1.12'), findsOneWidget);
    expect(
      find.text(
        'The last split is 0.12 mi; its pace is scaled to a full mile.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the workout notification follows the app language', (
    tester,
  ) async {
    final rig = WorkoutRig();
    await pumpScaled(
      tester,
      const OpenRingApp(),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('de'),
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
    for (final key in [
      AppNavigationBar.destinationKey(AppTab.activity),
      WorkoutEntryButton.startKey,
      WorkoutPickKeys.start,
    ]) {
      await reveal(tester, key);
      await tester.tap(find.byKey(key));
      await settle(tester);
    }

    expect(rig.location.listens, 1);
    expect(rig.location.notice?.title, 'OpenRing-Training');
    expect(rig.location.notice?.text, 'Deine Route wird aufgezeichnet');
    expect(rig.location.notice?.channel, 'Training');
  });
}
