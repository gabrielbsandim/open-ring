import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/activity/presentation/activity_screen.dart';
import 'package:open_ring/features/activity/presentation/hourly_steps_chart.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/workout/presentation/recent_workouts_card.dart';
import 'package:open_ring/features/workout/presentation/workout_entry_button.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/metrics_pump.dart';

void main() {
  testWidgets('without steps it says what to do', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const ActivityScreen()),
      noDataScenario,
    );

    expect(
      find.text('Steps and active energy show up here after the first sync.'),
      findsOneWidget,
    );
    expect(find.byKey(ActivityKeys.emptyAction), findsOneWidget);
    expect(find.byKey(ActivityKeys.hourly), findsNothing);
    expect(find.byKey(ActivityKeys.week), findsNothing);
  });

  testWidgets('shows today against the goal with its hourly bars', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpMetrics(
      tester,
      screenHost(const ActivityScreen()),
      fullDataScenario,
    );

    expect(find.text('2,224'), findsWidgets);
    expect(find.text('of 8,000'), findsOneWidget);
    expect(find.text('28%'), findsOneWidget);
    expect(find.byType(HourlyStepsChart), findsOneWidget);
    expect(
      find.bySemanticsLabel('Steps per hour. Peak at 18:00 with 620 steps.'),
      findsOneWidget,
    );
    expect(find.text('87 kcal'), findsOneWidget);
    expect(find.text('1.54 km'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the start button sits below the recent workouts', (
    tester,
  ) async {
    await pumpMetrics(
      tester,
      screenHost(const ActivityScreen()),
      fullDataScenario,
    );

    await tester.scrollUntilVisible(
      find.byKey(WorkoutEntryButton.startKey),
      200,
    );

    expect(
      tester.getTopLeft(find.byKey(WorkoutEntryButton.startKey)).dy,
      greaterThan(tester.getTopLeft(find.byType(RecentWorkoutsCard)).dy),
    );
    expect(find.text('Start workout'), findsOneWidget);
  });

  test('the start label follows the prototype in Portuguese', () {
    final l10n = lookupAppLocalizations(const Locale('pt'));

    expect(l10n.workoutStart, 'Iniciar treino');
    expect(l10n.workoutLocationStart, 'Começar treino');
  });

  testWidgets('lists the last 7 days with the estimate note', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const ActivityScreen()),
      fullDataScenario,
    );

    await tester.scrollUntilVisible(find.byKey(ActivityKeys.day(6)), 200);
    for (var i = 0; i < 7; i++) {
      expect(find.byKey(ActivityKeys.day(i)), findsOneWidget);
    }
    expect(find.byKey(ActivityKeys.day(7)), findsNothing);
    expect(find.text('Last 7 days'), findsOneWidget);
    expect(find.textContaining('Distance and active energy'), findsOneWidget);
  });

  testWidgets('a day without data says so', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const ActivityScreen()),
      buildingScenario,
    );

    await tester.scrollUntilVisible(find.byKey(ActivityKeys.day(6)), 200);
    expect(find.text('No data'), findsWidgets);
  });

  for (final c in layoutMatrix()) {
    testWidgets('imperial units show the distance in miles at $c', (
      tester,
    ) async {
      await pumpScaled(
        tester,
        screenHost(const ActivityScreen()),
        textScaler: c.textScaler,
        brightness: c.brightness,
        locale: c.locale,
        overrides: [
          ...metricsOverrides(fullDataScenario),
          unitSystemStoreProvider.overrideWithValue(
            InMemoryUnitSystemStore(UnitSystem.imperial),
          ),
        ],
      );

      final miles = c.locale.languageCode == 'de' ? '0,96 mi' : '0.96 mi';
      await tester.scrollUntilVisible(
        find.byKey(ActivityKeys.distance),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(
          of: find.byKey(ActivityKeys.distance),
          matching: find.text(miles),
        ),
        findsOneWidget,
      );
      expect(find.textContaining(' km'), findsNothing);
    });
  }
}
