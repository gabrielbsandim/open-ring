import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/sleep/presentation/hypnogram.dart';
import 'package:open_ring/features/sleep/presentation/sleep_score_breakdown.dart';
import 'package:open_ring/features/sleep/presentation/sleep_screen.dart';
import 'package:open_ring/features/today/presentation/formula_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/metrics_pump.dart';
import '../../../helpers/rem_reporting_fakes.dart';
import '../../../helpers/settings_fakes.dart';

Future<void> _pumpWithoutRem(
  WidgetTester tester, {
  RemReporting reporting = RemReporting.absent,
  TextScaler textScaler = TextScaler.noScaling,
  Brightness brightness = Brightness.dark,
  Locale locale = const Locale('en'),
}) => pumpScaled(
  tester,
  screenHost(const SleepScreen()),
  textScaler: textScaler,
  brightness: brightness,
  locale: locale,
  overrides: ringWithoutRemOverrides(reporting: reporting),
);

void main() {
  testWidgets('without a night it says what to do', (tester) async {
    await pumpMetrics(tester, screenHost(const SleepScreen()), noDataScenario);

    expect(find.textContaining('Wear your ring to bed'), findsOneWidget);
    expect(find.byKey(Hypnogram.chartKey), findsNothing);
  });

  testWidgets('without a ring and with a read on it points at Health Connect', (
    tester,
  ) async {
    await pumpScaled(
      tester,
      screenHost(const SleepScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: [
        ...metricsOverrides(noDataScenario),
        readsWithoutRingProvider.overrideWith((ref) async => true),
      ],
    );

    expect(find.text('No night from Health Connect yet.'), findsOneWidget);
    expect(find.textContaining('Wear your ring to bed'), findsNothing);
  });

  testWidgets('shows last night with its hypnogram and score inputs', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpMetrics(
      tester,
      screenHost(const SleepScreen()),
      fullDataScenario,
    );

    expect(find.text('Night of Nov 9 to Nov 10'), findsOneWidget);
    expect(find.text('6 h 52 min'), findsWidgets);
    expect(find.text('In bed 7 h 24 min · 23:18 to 06:42'), findsOneWidget);
    expect(find.byKey(Hypnogram.chartKey), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Light 3 h 46 min, deep 1 h 18 min')),
      findsWidgets,
    );
    expect(find.text('Where 95 comes from'), findsOneWidget);
    expect(find.text('Duration (goal 8 h)'), findsOneWidget);
    expect(find.byKey(SleepScreen.splitNoteKey), findsNothing);
    semantics.dispose();
  });

  testWidgets('a split night explains how it was joined', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const SleepScreen()),
      splitNightScenario,
    );

    expect(find.byKey(SleepScreen.splitNoteKey), findsOneWidget);
    expect(
      find.text(
        '2 stretches joined into one night: you woke at 04:12 for 9 min '
        'and went back to sleep.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('picking a day shows that night', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const SleepScreen()),
      fullDataScenario,
    );

    await tester.tap(find.byKey(SleepScreen.dayKey(0)));
    await tester.pumpAndSettle();

    expect(find.text('Night of Nov 3 to Nov 4'), findsOneWidget);
  });

  testWidgets('tapping the score shows its inputs', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const SleepScreen()),
      fullDataScenario,
    );

    await tester.tap(find.byKey(SleepScreen.scoreKey));
    await tester.pumpAndSettle();

    expect(find.text('Where 95 comes from'), findsNWidgets(2));
  });

  group('a ring that does not report REM', () {
    for (final c in layoutMatrix()) {
      testWidgets('lays out without overflow at $c', (tester) async {
        await _pumpWithoutRem(
          tester,
          textScaler: c.textScaler,
          brightness: c.brightness,
          locale: c.locale,
        );

        expect(find.byKey(Hypnogram.chartKey), findsOneWidget);
        await scrollThrough(tester);
        expect(find.byType(SleepScreen), findsOneWidget);
      });
    }

    testWidgets('hides the REM lane, its legend and its score input', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpWithoutRem(tester);

      expect(find.text('Light'), findsOneWidget);
      expect(find.text('REM'), findsNothing);
      expect(find.textContaining(RegExp('^REM ')), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r'deep [^,]+, awake [^.]+\.$')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Sleep stages through the night.*REM')),
        findsNothing,
      );
      await scrollThrough(tester);
      expect(find.text('Duration (goal 8 h)'), findsOneWidget);
      expect(find.text('REM sleep'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(SleepScoreBreakdown.weightsKey),
          matching: find.textContaining('does not report REM'),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('says so in German', (tester) async {
      await _pumpWithoutRem(tester, locale: const Locale('de'));
      await scrollThrough(tester);

      expect(find.text('REM'), findsNothing);
      expect(find.text('REM-Schlaf'), findsNothing);
      expect(
        find.textContaining('Dieser Ring meldet kein REM'),
        findsOneWidget,
      );
    });

    testWidgets('keeps REM while the ring is still being judged', (
      tester,
    ) async {
      await _pumpWithoutRem(tester, reporting: RemReporting.unknown);

      expect(find.text('REM'), findsOneWidget);
      await scrollThrough(tester);
      expect(find.text('REM sleep'), findsOneWidget);
      expect(find.textContaining('does not report REM'), findsNothing);
    });
  });

  testWidgets('the weights caption links to the formula', (tester) async {
    await pumpMetrics(tester, const OpenRingApp(), fullDataScenario);
    await tester.tap(find.byKey(AppNavigationBar.destinationKey(AppTab.sleep)));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(SleepScoreBreakdown.formulaLinkKey));

    await tester.tap(find.byKey(SleepScoreBreakdown.formulaLinkKey));
    await tester.pumpAndSettle();
    expect(find.byType(FormulaScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(SleepScreen), findsOneWidget);
    expect(find.byType(FormulaScreen), findsNothing);
  });
}
