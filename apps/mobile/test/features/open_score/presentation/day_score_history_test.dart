import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/open_score/presentation/day_score_history_screen.dart';
import 'package:open_ring/features/open_score/presentation/day_score_receipt_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/day_score_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import 'day_score_receipt_test.dart' show overridesFor, textOf;

GoRouter historyRouter({String at = AppPaths.dayScoreHistory}) => GoRouter(
  initialLocation: at,
  routes: [
    GoRoute(
      path: AppPaths.dayScore,
      builder: (_, state) => DayScoreReceiptScreen(
        day: LocalDate.tryParse(state.uri.queryParameters['day']),
      ),
      routes: [
        GoRoute(
          path: 'history',
          builder: (_, _) => const DayScoreHistoryScreen(),
        ),
      ],
    ),
  ],
);

Future<GoRouter> pumpHistory(
  WidgetTester tester,
  DayScoreHistory? history, {
  Set<ModuleId> modules = const {ModuleId.openScore},
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  String at = AppPaths.dayScoreHistory,
}) async {
  final router = historyRouter(at: at);
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
    textScaler: textScaler,
    brightness: Brightness.dark,
    locale: locale,
    overrides: overridesFor(history, modules: modules),
    size: const Size(360, 8000),
  );
  return router;
}

Future<void> show(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> tapBar(WidgetTester tester, int index, int days) async {
  final chart = tester.getRect(find.byKey(DayScoreHistoryKeys.chart));
  const left = 26.0;
  final slot = (chart.width - left) / days;
  await tester.tapAt(
    Offset(chart.left + left + (index + 0.5) * slot, chart.center.dy),
  );
  await tester.pumpAndSettle();
}

IconButton button(WidgetTester tester, Key key) =>
    tester.widget<IconButton>(find.byKey(key));

void main() {
  test('the average counts closed days with full coverage only', () {
    final average = mixedHistory().fullAverage(30);

    expect(average?.count, 27);
    expect(average?.value, ((88 + 26 * 94) / 27).round());
    expect(historyOf(day()).fullAverage(30)?.count, 1);
    expect(historyOf(day(), scoredBefore: false).fullAverage(30), isNull);
  });

  testWidgets('before the first score it offers today', (tester) async {
    final router = await pumpHistory(
      tester,
      historyOf(day(sleepScore: null), scoredBefore: false),
    );

    expect(find.byKey(DayScoreHistoryKeys.empty), findsOneWidget);
    expect(find.byKey(DayScoreHistoryKeys.view), findsNothing);

    await tester.tap(find.byKey(DayScoreHistoryKeys.emptyAction));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), AppPaths.dayScore);
  });

  testWidgets('the calendar shows each day of the month', (tester) async {
    await pumpHistory(tester, mixedHistory());

    expect(textOf(tester, DayScoreHistoryKeys.month), 'November 2026');
    Finder inDay(int age, String text) => find.descendant(
      of: find.byKey(DayScoreHistoryKeys.day(metricsToday.addDays(-age))),
      matching: find.text(text),
    );
    expect(inDay(0, '94'), findsOneWidget);
    expect(inDay(1, '84'), findsOneWidget);
    expect(inDay(2, '·'), findsOneWidget);
    expect(
      find.byKey(DayScoreHistoryKeys.day(metricsToday.addDays(1))),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel(RegExp('score 84, Good day, coverage 85 of 100')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(', no score')), findsOneWidget);
    expect(button(tester, DayScoreHistoryKeys.nextMonth).onPressed, isNull);
  });

  testWidgets('the month arrows stop where the history starts', (tester) async {
    await pumpHistory(tester, mixedHistory());

    await tester.tap(find.byKey(DayScoreHistoryKeys.previousMonth));
    await tester.pumpAndSettle();

    expect(textOf(tester, DayScoreHistoryKeys.month), 'October 2026');
    expect(button(tester, DayScoreHistoryKeys.previousMonth).onPressed, isNull);
    expect(
      find.byKey(DayScoreHistoryKeys.day(const LocalDate(2026, 10, 1))),
      findsNothing,
    );
    expect(
      find.byKey(DayScoreHistoryKeys.day(const LocalDate(2026, 10, 2))),
      findsOneWidget,
    );
  });

  testWidgets('tapping a day opens its receipt', (tester) async {
    final router = await pumpHistory(tester, mixedHistory());
    final yesterday = metricsToday.addDays(-1);

    await tester.tap(find.byKey(DayScoreHistoryKeys.day(yesterday)));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/today/day-score?day=2026-11-09');
    expect(textOf(tester, DayScoreReceiptKeys.day), startsWith('Yesterday, '));
    expect(textOf(tester, DayScoreReceiptKeys.status), 'final score');
  });

  testWidgets('a day picked in the history wins over the arrows', (
    tester,
  ) async {
    await pumpHistory(tester, mixedHistory(), at: AppPaths.dayScore);

    await tester.tap(find.byKey(DayScoreReceiptKeys.previous));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(DayScoreReceiptKeys.history));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(DayScoreHistoryKeys.day(metricsToday)));
    await tester.pumpAndSettle();

    expect(textOf(tester, DayScoreReceiptKeys.day), startsWith('Today, '));
  });

  testWidgets('a day outside the history falls back to today', (tester) async {
    await pumpHistory(
      tester,
      mixedHistory(),
      at: '/today/day-score?day=2020-01-01',
    );

    expect(textOf(tester, DayScoreReceiptKeys.day), startsWith('Today, '));
  });

  testWidgets('the bars show the average and the day that was tapped', (
    tester,
  ) async {
    final router = await pumpHistory(tester, mixedHistory());

    await show(tester, '30 days');

    expect(
      find.descendant(
        of: find.byKey(DayScoreHistoryKeys.average),
        matching: find.text('Average of the 27 closed days with full coverage'),
      ),
      findsOneWidget,
    );
    expect(find.text('Tap a bar to see the day.'), findsOneWidget);

    await tapBar(tester, 28, 30);

    final readout = find.byKey(DayScoreHistoryKeys.readout);
    expect(
      find.descendant(of: readout, matching: find.text('84 · Good day')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: readout, matching: find.text('85 of 100 points')),
      findsOneWidget,
    );

    await tapBar(tester, 27, 30);

    expect(
      find.descendant(of: readout, matching: find.text('Day without a score')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(DayScoreHistoryKeys.open));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/today/day-score?day=2026-11-08');
  });

  testWidgets('ninety days keeps the days the history does not have blank', (
    tester,
  ) async {
    await pumpHistory(tester, mixedHistory());

    await show(tester, '90 days');
    await tapBar(tester, 89, 90);

    expect(
      find.descendant(
        of: find.byKey(DayScoreHistoryKeys.readout),
        matching: find.text('94 · Great day'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('with Open Score off the screen shows nothing', (tester) async {
    await pumpHistory(tester, mixedHistory(), modules: const {});

    expect(find.byKey(DayScoreHistoryKeys.view), findsNothing);
    expect(find.byKey(DayScoreHistoryKeys.empty), findsNothing);
  });

  for (final view in ['Kalender', '30 Tage']) {
    testWidgets('$view fits at twice the text size in German', (tester) async {
      await pumpHistory(
        tester,
        mixedHistory(),
        locale: const Locale('de'),
        textScaler: const TextScaler.linear(2),
      );

      await show(tester, view);
      if (view != 'Kalender') await tapBar(tester, 28, 30);

      expect(find.byKey(DayScoreHistoryKeys.view), findsOneWidget);
    });
  }
}
