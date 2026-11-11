import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/today/presentation/formula_screen.dart';
import 'package:open_ring/features/today/presentation/readiness_screen.dart';
import 'package:open_ring/features/today/presentation/today_cards.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/metrics_pump.dart';
import '../../../helpers/settings_fakes.dart';

void main() {
  testWidgets('with full data shows each input and its points', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const ReadinessScreen()),
      fullDataScenario,
    );

    for (final factor in ReadinessFactor.values) {
      expect(find.byKey(ReadinessScreen.factorKey(factor)), findsOneWidget);
    }
    expect(find.text('Sleep score'), findsOneWidget);
    expect(find.text('46 ms'), findsOneWidget);
    expect(find.textContaining('baseline'), findsWidgets);
    expect(find.textContaining(' of 35 pts'), findsOneWidget);
    expect(find.byKey(ReadinessScreen.totalKey), findsOneWidget);
    expect(
      find.textContaining('compared with your baseline of 27 nights'),
      findsOneWidget,
    );
    expect(find.byKey(EstimateNote.noteKey), findsOneWidget);
    expect(
      find.textContaining('Estimate, not a medical diagnosis.'),
      findsOneWidget,
    );
  });

  testWidgets('while building it says what is missing and why', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const ReadinessScreen()),
      buildingScenario,
    );

    expect(
      find.textContaining('Learning your baseline: 2 of 7 nights.'),
      findsWidgets,
    );
    expect(
      find.textContaining('Needs activity on at least 14'),
      findsOneWidget,
    );
    expect(find.text('Not scored'), findsOneWidget);
    expect(find.text('up to 35 pts'), findsOneWidget);
  });

  testWidgets('with no data every input says what to do', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const ReadinessScreen()),
      noDataScenario,
    );

    expect(find.textContaining('Readiness needs'), findsOneWidget);
    expect(find.textContaining('No scored night yet'), findsOneWidget);
    expect(find.textContaining('No reading from last night'), findsNWidgets(2));
  });

  testWidgets('shows the last 14 days with their average', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpMetrics(
      tester,
      screenHost(const ReadinessScreen()),
      fullDataScenario,
    );

    await reveal(tester, find.byKey(ReadinessScreen.trendKey));
    expect(find.text('Last 14 days'), findsOneWidget);
    expect(find.byKey(ReadinessScreen.trendAverageKey), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Readiness over the last 14 days, from')),
      findsOneWidget,
    );
    expect(find.byKey(ReadinessScreen.trendEmptyKey), findsNothing);
    semantics.dispose();
  });

  testWidgets('with no scored day the trend says so', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const ReadinessScreen()),
      buildingScenario,
    );

    await reveal(tester, find.byKey(ReadinessScreen.trendEmptyKey));
    expect(find.byKey(ReadinessScreen.trendAverageKey), findsNothing);
  });

  testWidgets('How we calculate opens the formula and comes back', (
    tester,
  ) async {
    await pumpMetrics(tester, const OpenRingApp(), fullDataScenario);
    await reveal(tester, find.byKey(TodayKeys.readiness));
    await tester.tap(find.byKey(TodayKeys.readiness));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(ReadinessScreen.formulaLinkKey));

    await tester.tap(find.byKey(ReadinessScreen.formulaLinkKey));
    await tester.pumpAndSettle();
    expect(find.byType(FormulaScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ReadinessScreen), findsOneWidget);
    expect(find.byType(FormulaScreen), findsNothing);
  });

  for (final c in layoutMatrix()) {
    for (final (name, scenario) in [
      ('full data', fullDataScenario),
      ('a building baseline', buildingScenario),
    ]) {
      testWidgets('lays out with $name at $c', (tester) async {
        await pumpScaled(
          tester,
          screenHost(const ReadinessScreen()),
          textScaler: c.textScaler,
          brightness: c.brightness,
          locale: c.locale,
          overrides: metricsOverrides(scenario),
        );

        await scrollThrough(tester);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
