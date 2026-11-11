import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/activity/presentation/activity_screen.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/recent_workouts_card.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/workout_fakes.dart';
import '../../workout/presentation/workout_scenarios.dart';

MemoryWorkoutHistory _history() => MemoryWorkoutHistory(
  seed: [
    savedRun(id: 1, startAfter: const Duration(days: -4)),
    savedRun(
      id: 2,
      type: WorkoutType.walking,
      startAfter: const Duration(days: -1),
      health: WorkoutHealthStatus.pending,
    ),
    savedRun(id: 3, type: WorkoutType.yoga),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  required WorkoutHistoryReader history,
  LayoutCase c = const LayoutCase(
    scale: 1,
    brightness: Brightness.dark,
    locale: Locale('en'),
  ),
}) => pumpScaled(
  tester,
  screenHost(const ActivityScreen()),
  textScaler: c.textScaler,
  brightness: c.brightness,
  locale: c.locale,
  overrides: [
    ...metricsOverrides(fullDataScenario),
    workoutHistoryReaderProvider.overrideWithValue(history),
  ],
);

Future<void> _reveal(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists recent workouts newest first with their Health state', (
    tester,
  ) async {
    await _pump(tester, history: _history());

    await _reveal(tester, RecentWorkoutsKeys.item(1));
    expect(find.text('Recent workouts'), findsOneWidget);
    final rows = [
      for (final id in [3, 2, 1])
        tester.getTopLeft(find.byKey(RecentWorkoutsKeys.item(id))).dy,
    ];
    expect(rows, orderedEquals([...rows]..sort()));
    expect(find.text('Yoga'), findsOneWidget);
    expect(find.text('Today · 10 min · avg HR 144'), findsOneWidget);
    expect(find.text('Yesterday · 10 min · avg HR 144'), findsOneWidget);
    expect(find.text('Waiting for Health Connect'), findsOneWidget);
    expect(find.text('In Health Connect'), findsNWidgets(2));
  });

  testWidgets('without workouts it says how to record one', (tester) async {
    await _pump(tester, history: const EmptyWorkoutHistoryReader());

    await _reveal(tester, RecentWorkoutsKeys.empty);
    expect(
      find.text(
        'No workouts yet. Tap "Start workout" to record your first one.',
      ),
      findsOneWidget,
    );
  });

  group('layout', () {
    for (final c in layoutMatrix()) {
      testWidgets('recent workouts lay out without overflow at $c', (
        tester,
      ) async {
        await _pump(tester, history: _history(), c: c);

        await expectNoLayoutOverflow(
          () => _reveal(tester, RecentWorkoutsKeys.item(1)),
        );
        expect(find.byKey(RecentWorkoutsKeys.card), findsOneWidget);
      });
    }
  });
}
