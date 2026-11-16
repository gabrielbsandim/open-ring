import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/energy/presentation/energy_row.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/application/day_score_view.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/open_score/presentation/day_score_card.dart';
import 'package:open_ring/features/today/presentation/today_cards.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/day_score_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';

Future<void> pumpCard(
  WidgetTester tester,
  DayScoreHistory? history, {
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
}) => pumpScaled(
  tester,
  screenHost(
    const Scaffold(body: SingleChildScrollView(child: DayScoreCard())),
  ),
  textScaler: textScaler,
  brightness: Brightness.dark,
  locale: locale,
  overrides: <Override>[
    clockProvider.overrideWithValue(() => metricsNow),
    dayScoreHistoryProvider.overrideWith((ref) async {
      if (history == null) throw StateError('no database');
      return history;
    }),
  ],
);

Future<void> pumpToday(
  WidgetTester tester,
  Set<ModuleId> modules, {
  MetricsScenario? scenario,
}) => pumpScaled(
  tester,
  screenHost(const TodayScreen()),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  size: const Size(360, 3000),
  overrides: <Override>[
    ...metricsOverrides(scenario ?? fullDataScenario),
    moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
  ],
);

String _label(WidgetTester tester, Key key) => tester
    .widget<Text>(
      find.descendant(of: find.byKey(key), matching: find.byType(Text)),
    )
    .data!;

GoRouter _router() => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) =>
          const Scaffold(body: SingleChildScrollView(child: DayScoreCard())),
    ),
    for (final path in [
      AppPaths.dayScore,
      AppPaths.dayScoreHistory,
      AppPaths.dayScoreFormula,
    ])
      GoRoute(
        path: path,
        builder: (_, _) => Scaffold(body: Text(path)),
      ),
  ],
);

String textOf(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

void main() {
  group('the view', () {
    test('reads points on the published scale', () {
      final scored =
          day(steps: 4000, stressZ: null, spo2Mean: null).score
              as Scored<DayScoreFactor>;

      expect(scored.earned(factorsOf(DayScorePillar.movement)), 27.5);
      expect(scored.available(factorsOf(DayScorePillar.movement)), 35);
      expect(scored.available(factorsOf(DayScorePillar.stress)), 0);
      expect(scored.open, 7.5);
    });

    test('names the reason a day has no score', () {
      InsufficientData<DayScoreFactor> lacking(
        ScoreResult<DayScoreFactor> result,
      ) => result as InsufficientData<DayScoreFactor>;
      final thin = lacking(
        day(intensityMinutes: null, baselines: false, spo2Mean: null).score,
      );

      expect(
        lacking(day(sleepScore: null, steps: 0).score).gap,
        DayScoreGap.night,
      );
      expect(lacking(day(steps: 0).score).gap, DayScoreGap.steps);
      expect(thin.gap, DayScoreGap.coverage);
      expect(thin.coverage, 55);
      expect(thin.has(DayScoreFactor.stress), isTrue);
      expect(thin.has(DayScoreFactor.hrv), isFalse);
    });
  });

  group('on Today', () {
    testWidgets('with Open Score off there is no card', (tester) async {
      await pumpToday(tester, const {});

      expect(find.byKey(DayScoreCardKeys.card), findsNothing);
    });

    testWidgets('with Open Score on the card comes first', (tester) async {
      await pumpToday(tester, const {ModuleId.openScore});

      final card = tester.getTopLeft(find.byKey(DayScoreCardKeys.card)).dy;
      final readiness = tester.getTopLeft(find.byKey(TodayKeys.readiness)).dy;
      expect(card, lessThan(readiness));
      expect(find.byKey(DayScoreCardKeys.value), findsOneWidget);
    });

    testWidgets('with Energy off there is no energy row', (tester) async {
      await pumpToday(tester, const {ModuleId.openScore});

      expect(find.byKey(EnergyRowKeys.row), findsNothing);
    });

    testWidgets('with no module on there is no energy row', (tester) async {
      await pumpToday(tester, const {});

      expect(find.byKey(EnergyRowKeys.row), findsNothing);
    });

    testWidgets('with Energy on the row sits right after the Day Score', (
      tester,
    ) async {
      await pumpToday(tester, const {ModuleId.openScore, ModuleId.energy});

      final card = tester.getBottomLeft(find.byKey(DayScoreCardKeys.card)).dy;
      final row = tester.getTopLeft(find.byKey(EnergyRowKeys.row)).dy;
      final readiness = tester.getTopLeft(find.byKey(TodayKeys.readiness)).dy;
      expect(find.byKey(EnergyRowKeys.row), findsOneWidget);
      expect(row, greaterThanOrEqualTo(card));
      expect(row, lessThan(readiness));
    });

    testWidgets('with only Energy on the row comes before the readiness', (
      tester,
    ) async {
      await pumpToday(tester, const {ModuleId.energy});

      final row = tester.getTopLeft(find.byKey(EnergyRowKeys.row)).dy;
      final readiness = tester.getTopLeft(find.byKey(TodayKeys.readiness)).dy;
      expect(find.byKey(DayScoreCardKeys.card), findsNothing);
      expect(row, lessThan(readiness));
    });

    testWidgets('when the ring is stale the row still follows the Day Score', (
      tester,
    ) async {
      await pumpToday(tester, const {
        ModuleId.openScore,
        ModuleId.energy,
      }, scenario: offlineScenario);

      final offline = tester.getTopLeft(find.byKey(TodayKeys.offline)).dy;
      final card = tester.getBottomLeft(find.byKey(DayScoreCardKeys.card)).dy;
      final row = tester.getTopLeft(find.byKey(EnergyRowKeys.row)).dy;
      final readiness = tester.getTopLeft(find.byKey(TodayKeys.readiness)).dy;
      expect(offline, lessThan(card));
      expect(row, greaterThanOrEqualTo(card));
      expect(row, lessThan(readiness));
    });

    testWidgets('a single row shows on Today with the stale ring', (
      tester,
    ) async {
      await pumpToday(tester, const {
        ModuleId.energy,
      }, scenario: offlineScenario);

      expect(find.byKey(EnergyRowKeys.row), findsOneWidget);
    });
  });

  group('the card', () {
    testWidgets('a full day shows the number, the band and the points', (
      tester,
    ) async {
      await pumpCard(tester, historyOf(day()));

      expect(textOf(tester, DayScoreCardKeys.value), '94');
      expect(textOf(tester, DayScoreCardKeys.band), 'Great day');
      expect(find.text('Full coverage'), findsOneWidget);
      expect(find.text('so far · 09:00'), findsOneWidget);
      expect(find.text('Sleep 24/30'), findsOneWidget);
      expect(find.text('Movement 35/35'), findsOneWidget);
      expect(
        find.text('Nothing open: the score closes at midnight.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Day Score 94 of 100, Great day, Full coverage'),
        findsOneWidget,
      );
    });

    testWidgets('a day in progress says how much movement is open', (
      tester,
    ) async {
      await pumpCard(tester, historyOf(day(steps: 4000)));

      expect(
        find.text('Open until midnight: up to 8 movement points.'),
        findsOneWidget,
      );
    });

    testWidgets('partial coverage names what stayed out', (tester) async {
      await pumpCard(tester, historyOf(day(stressZ: null, spo2Mean: null)));

      expect(find.text('85 of 100 points'), findsOneWidget);
      expect(find.text('Stress: left out'), findsOneWidget);
      expect(find.text('Oxygen: left out'), findsOneWidget);
      expect(
        find.text(
          'Left out: stress, SpO2. The score counts over 85 points and '
          'was rescaled.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a low score gets a neutral word', (tester) async {
      await pumpCard(
        tester,
        historyOf(day(sleepScore: 30, steps: 1000, intensityMinutes: 0)),
      );

      expect(textOf(tester, DayScoreCardKeys.band), 'Pause day');
    });

    testWidgets('without the night there is no score and no blame', (
      tester,
    ) async {
      await pumpCard(tester, historyOf(day(sleepScore: null)));

      expect(find.byKey(DayScoreCardKeys.none), findsOneWidget);
      expect(find.byKey(DayScoreCardKeys.value), findsNothing);
      expect(find.text('No score today'), findsOneWidget);
      expect(find.textContaining('The night is missing'), findsOneWidget);
      expect(find.textContaining('does not count against you'), findsOneWidget);
    });

    testWidgets('zero steps reads as the ring off the finger', (tester) async {
      await pumpCard(tester, historyOf(day(steps: 0)));

      expect(find.textContaining('Zero steps reads as'), findsOneWidget);
    });

    testWidgets('thin coverage says how many points were there', (
      tester,
    ) async {
      await pumpCard(
        tester,
        historyOf(
          day(intensityMinutes: null, baselines: false, spo2Mean: null),
        ),
      );

      expect(
        find.textContaining('Today only 55 of the 100 points'),
        findsOneWidget,
      );
    });

    testWidgets('before any score the card shows what is still building', (
      tester,
    ) async {
      await pumpCard(
        tester,
        historyOf(
          day(intensityMinutes: null, baselines: false, stressZ: null),
          scoredBefore: false,
        ),
      );

      expect(find.byKey(DayScoreCardKeys.first), findsOneWidget);
      expect(find.byKey(DayScoreCardKeys.none), findsNothing);
      expect(find.text('Your first score is on its way'), findsOneWidget);
      expect(find.textContaining('Today there are 50'), findsOneWidget);
      expect(find.text('ready'), findsNWidgets(2));
      expect(find.text('building'), findsNWidgets(2));
    });

    testWidgets('the first days count the active days and the baselines', (
      tester,
    ) async {
      await pumpCard(
        tester,
        DayScoreHistory(
          today: metricsToday,
          days: {
            metricsToday: day(
              intensityMinutes: null,
              baselines: false,
              stressZ: null,
            ),
          },
          progress: (
            activeDays: 3,
            activeNeeded: 4,
            baselineDays: 2,
            baselineNeeded: 7,
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(DayScoreCardKeys.firstActivity),
          matching: find.text('3 of 4'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(DayScoreCardKeys.firstBaselines),
          matching: find.text('2 of 7'),
        ),
        findsOneWidget,
      );
      expect(find.text('building'), findsNothing);
      expect(find.text('ready'), findsNWidgets(2));
    });

    testWidgets('a rule that is met reads ready, not a count', (tester) async {
      await pumpCard(
        tester,
        DayScoreHistory(
          today: metricsToday,
          days: {metricsToday: day(baselines: false, stressZ: null, steps: 0)},
          progress: (
            activeDays: 5,
            activeNeeded: 4,
            baselineDays: 6,
            baselineNeeded: 7,
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(DayScoreCardKeys.firstActivity),
          matching: find.text('ready'),
        ),
        findsOneWidget,
      );
      expect(find.text('5 of 4'), findsNothing);
      expect(find.text('6 of 7'), findsOneWidget);
    });

    testWidgets('a day without a score draws the bar of what was there', (
      tester,
    ) async {
      await pumpCard(tester, historyOf(day(sleepScore: null)));

      final bar = tester.widget<DayScoreBar>(
        find.byKey(DayScoreCardKeys.noneBar),
      );
      expect(bar.subscore(DayScoreFactor.sleep), isNull);
      expect(bar.subscore(DayScoreFactor.steps), 1);
    });

    testWidgets('a scored day links to the math and the score history', (
      tester,
    ) async {
      await pumpCard(tester, historyOf(day()));

      expect(_label(tester, DayScoreCardKeys.openReceipt), 'See the math');
      expect(_label(tester, DayScoreCardKeys.openOther), 'Score history');
    });

    testWidgets('a day without a score links to what was missing', (
      tester,
    ) async {
      await pumpCard(tester, historyOf(day(sleepScore: null)));

      expect(
        _label(tester, DayScoreCardKeys.openReceipt),
        'See what was missing',
      );
      expect(_label(tester, DayScoreCardKeys.openOther), 'Score history');
    });

    testWidgets('the first days link to the math and the formula', (
      tester,
    ) async {
      await pumpCard(
        tester,
        historyOf(
          day(intensityMinutes: null, baselines: false, stressZ: null),
          scoredBefore: false,
        ),
      );

      expect(_label(tester, DayScoreCardKeys.openReceipt), 'See the math');
      expect(_label(tester, DayScoreCardKeys.openOther), 'How we calculate');
    });

    testWidgets('a failed read has no link', (tester) async {
      await pumpCard(tester, null);

      expect(find.byKey(DayScoreCardKeys.openReceipt), findsNothing);
      expect(find.byKey(DayScoreCardKeys.openOther), findsNothing);
    });

    for (final (name, history, path) in [
      ('a scored day', historyOf(day()), AppPaths.dayScoreHistory),
      (
        'the first days',
        historyOf(
          day(intensityMinutes: null, baselines: false, stressZ: null),
          scoredBefore: false,
        ),
        AppPaths.dayScoreFormula,
      ),
    ]) {
      testWidgets('the links of $name open their screens', (tester) async {
        final router = _router();
        addTearDown(router.dispose);
        await pumpScaled(
          tester,
          MaterialApp.router(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            supportedLocales: AppLocales.supported,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            routerConfig: router,
          ),
          textScaler: TextScaler.noScaling,
          brightness: Brightness.dark,
          locale: const Locale('en'),
          overrides: <Override>[
            clockProvider.overrideWithValue(() => metricsNow),
            dayScoreHistoryProvider.overrideWith((ref) async => history),
          ],
        );

        await tester.tap(find.byKey(DayScoreCardKeys.openOther));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, path);

        router.go('/');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(DayScoreCardKeys.openReceipt));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, AppPaths.dayScore);
      });
    }

    testWidgets('a failed read says so', (tester) async {
      await pumpCard(tester, null);

      expect(find.byKey(DayScoreCardKeys.value), findsNothing);
      expect(find.byKey(DayScoreCardKeys.card), findsOneWidget);
    });

    testWidgets('reads in Portuguese', (tester) async {
      await pumpCard(tester, historyOf(day()), locale: const Locale('pt'));

      expect(find.text('Nota do Dia'), findsOneWidget);
      expect(textOf(tester, DayScoreCardKeys.band), 'Dia ótimo');
      expect(find.text('Cobertura completa'), findsOneWidget);
    });

    for (final history in [
      historyOf(day(stressZ: null, spo2Mean: null)),
      historyOf(day(sleepScore: null)),
      historyOf(
        day(intensityMinutes: null, baselines: false, stressZ: null),
        scoredBefore: false,
      ),
    ]) {
      testWidgets('fits a narrow phone at twice the text size', (tester) async {
        await pumpCard(
          tester,
          history,
          locale: const Locale('de'),
          textScaler: const TextScaler.linear(2),
        );

        expect(tester.takeException(), isNull);
      });
    }
  });
}
