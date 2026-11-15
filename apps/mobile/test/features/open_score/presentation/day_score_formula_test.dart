import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/features/open_score/presentation/day_score_formula_screen.dart';
import 'package:open_ring/features/open_score/presentation/day_score_receipt_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/day_score_fakes.dart';
import '../../../helpers/layout_harness.dart';
import 'day_score_receipt_test.dart' show overridesFor;

Future<void> pumpFormula(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
}) => pumpScaled(
  tester,
  screenHost(const DayScoreFormulaScreen()),
  textScaler: textScaler,
  brightness: Brightness.dark,
  locale: locale,
  overrides: const [],
  size: const Size(360, 24000),
);

Finder within(Key key, String text) =>
    find.descendant(of: find.byKey(key), matching: find.text(text));

void main() {
  test('the numbers the screen prints match the constants', () {
    expect([stressZeroZ, stressFullZ], [3, -1]);
    expect([spo2ZeroAt, spo2FullAt], [90, 95]);
    expect(intensityWeeklyTarget, 150);
    expect([intensityWindowDays, baselineWindowDays], [7, 28]);
    expect(dayScoreMinCoverage, 60);
    expect([moderateFraction, vigorousFraction], [0.64, 0.77]);
    expect([moderateMet, vigorousMet, vigorousMinuteWeight], [3, 6, 2]);
    expect(briskStepsPerMinute, 100);
    expect(DayScoreFactor.intensity.weight, 20);
  });

  testWidgets('lists the seven factors with weights that add up', (
    tester,
  ) async {
    await pumpFormula(tester);

    for (final factor in DayScoreFactor.values) {
      expect(find.byKey(DayScoreFormulaKeys.factor(factor)), findsOneWidget);
    }
    expect(
      within(DayScoreFormulaKeys.factor(DayScoreFactor.sleep), '30'),
      findsOneWidget,
    );
    expect(
      within(
        DayScoreFormulaKeys.factor(DayScoreFactor.hrv),
        'Last night against your HRV baseline, as z: 0 points at z −3, '
        'all of them at z +1.',
      ),
      findsOneWidget,
    );
    expect(within(DayScoreFormulaKeys.total, '100'), findsOneWidget);
    expect(
      within(
        DayScoreFormulaKeys.total,
        'Sleep 30, Movement 35, Recovery 20, Stress 10, Oxygen 5',
      ),
      findsOneWidget,
    );
    expect(
      find.text('score = 100 × points earned ÷ points of the factors present'),
      findsOneWidget,
    );
  });

  testWidgets('gives each band its range', (tester) async {
    await pumpFormula(tester);

    final ranges = {
      DayScoreBand.great: ('Great day', '85 to 100'),
      DayScoreBand.good: ('Good day', '70 to 84'),
      DayScoreBand.mixed: ('Mixed day', '55 to 69'),
      DayScoreBand.low: ('Pause day', '0 to 54'),
    };
    for (final MapEntry(key: band, value: (name, range)) in ranges.entries) {
      expect(within(DayScoreFormulaKeys.band(band), name), findsOneWidget);
      expect(within(DayScoreFormulaKeys.band(band), range), findsOneWidget);
    }
  });

  testWidgets('names the sources and what is our own choice', (tester) async {
    await pumpFormula(tester);

    expect(find.textContaining('World Health Organization 2020'), findsOne);
    expect(find.textContaining('Garber CE'), findsOne);
    expect(find.textContaining('Tudor-Locke C'), findsOne);
    expect(within(DayScoreFormulaKeys.sources, 'Our choice'), findsOneWidget);
  });

  testWidgets('fits at twice the text size in German', (tester) async {
    await pumpFormula(
      tester,
      locale: const Locale('de'),
      textScaler: const TextScaler.linear(2),
    );

    expect(find.byKey(DayScoreFormulaKeys.sources), findsOneWidget);
  });

  testWidgets('the receipt links to the formula', (tester) async {
    final router = GoRouter(
      initialLocation: AppPaths.dayScore,
      routes: [
        GoRoute(
          path: AppPaths.dayScore,
          builder: (_, _) => const DayScoreReceiptScreen(),
          routes: [
            GoRoute(
              path: 'formula',
              builder: (_, _) => const DayScoreFormulaScreen(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpScaled(
      tester,
      MaterialApp.router(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        localeListResolutionCallback: AppLocales.resolve,
        supportedLocales: AppLocales.supported,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
      ),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: overridesFor(historyOf(day())),
      size: const Size(360, 6000),
    );

    await tester.tap(find.byKey(DayScoreReceiptKeys.formula));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppPaths.dayScoreFormula);
    expect(find.byKey(DayScoreFormulaKeys.expression), findsOneWidget);
  });
}
