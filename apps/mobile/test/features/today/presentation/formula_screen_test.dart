import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/today/presentation/formula_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/metrics_pump.dart';
import '../../../helpers/rem_reporting_fakes.dart';
import '../../../helpers/settings_fakes.dart';

Finder _inside(Key row, Finder matching) =>
    find.descendant(of: find.byKey(row), matching: matching);

void main() {
  testWidgets('says the scores are estimates, not a diagnosis', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const FormulaScreen()),
      fullDataScenario,
    );

    expect(find.text('How we calculate'), findsOneWidget);
    expect(find.textContaining('is an estimate from the ring'), findsOneWidget);
    expect(find.textContaining('docs/metrics.md'), findsOneWidget);
    await reveal(tester, find.byKey(EstimateNote.noteKey));
    expect(find.byKey(EstimateNote.noteKey), findsOneWidget);
  });

  testWidgets('every readiness input has its rule, weight and today', (
    tester,
  ) async {
    await pumpMetrics(
      tester,
      screenHost(const FormulaScreen()),
      fullDataScenario,
    );

    for (final factor in ReadinessFactor.values) {
      final row = FormulaScreen.readinessFactorKey(factor);
      await reveal(tester, find.byKey(row));
      expect(_inside(row, find.textContaining('Today: ')), findsOneWidget);
      expect(
        _inside(row, find.textContaining(RegExp(r' of \d+(\.\d)? pts$'))),
        findsOneWidget,
      );
    }
    final hrv = FormulaScreen.readinessFactorKey(ReadinessFactor.hrv);
    await reveal(tester, find.byKey(hrv));
    expect(
      _inside(
        hrv,
        find.textContaining('0 points at z −3, all of them at z +1.'),
      ),
      findsOneWidget,
    );
    expect(_inside(hrv, find.textContaining('Today: 46 ms')), findsOneWidget);
    final sleep = FormulaScreen.readinessFactorKey(ReadinessFactor.sleep);
    await reveal(tester, find.byKey(sleep));
    expect(_inside(sleep, find.text('Today: 95')), findsOneWidget);
    expect(_inside(sleep, find.text('33.3 of 35 pts')), findsOneWidget);
  });

  testWidgets('every sleep input has its rule, weight and today', (
    tester,
  ) async {
    await pumpMetrics(
      tester,
      screenHost(const FormulaScreen()),
      fullDataScenario,
    );

    for (final factor in SleepFactor.values) {
      final row = FormulaScreen.sleepFactorKey(factor);
      await reveal(tester, find.byKey(row));
      expect(_inside(row, find.textContaining('Today: ')), findsOneWidget);
    }
    final duration = FormulaScreen.sleepFactorKey(SleepFactor.duration);
    await reveal(tester, find.byKey(duration));
    expect(_inside(duration, find.text('Today: 6 h 52 min')), findsOneWidget);
    expect(_inside(duration, find.textContaining('goal of 8 h')), findsWidgets);
  });

  testWidgets('without data it keeps the rules and says what is missing', (
    tester,
  ) async {
    await pumpMetrics(
      tester,
      screenHost(const FormulaScreen()),
      noDataScenario,
    );

    await reveal(tester, find.textContaining('Readiness needs'));
    expect(find.textContaining('Readiness needs'), findsOneWidget);
    await reveal(tester, find.textContaining('Too short to score'));
    expect(find.textContaining('Too short to score'), findsOneWidget);
    expect(find.text('Not scored'), findsWidgets);
  });

  testWidgets('a ring that does not report REM has no REM row', (tester) async {
    await pumpScaled(
      tester,
      screenHost(const FormulaScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: todayWithoutRemOverrides(),
    );

    await scrollThrough(tester);
    expect(
      find.byKey(FormulaScreen.sleepFactorKey(SleepFactor.rem)),
      findsNothing,
    );
    expect(find.textContaining('does not report REM'), findsOneWidget);
  });

  for (final c in layoutMatrix()) {
    for (final (name, scenario) in [
      ('full data', fullDataScenario),
      ('no data', noDataScenario),
    ]) {
      testWidgets('lays out with $name at $c', (tester) async {
        await pumpScaled(
          tester,
          screenHost(const FormulaScreen()),
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
