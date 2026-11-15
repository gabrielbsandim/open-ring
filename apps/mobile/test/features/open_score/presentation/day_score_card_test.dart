import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/application/day_score_view.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/open_score/presentation/day_score_card.dart';
import 'package:open_ring/features/today/presentation/today_cards.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';

BaselineDeviation z(double zScore) =>
    BaselineDeviation(today: 1, baseline: 1, zScore: zScore);

ScoreResult<DayScoreFactor> day({
  int? sleepScore = 80,
  int? steps = 8000,
  double? intensityMinutes = 150,
  bool baselines = true,
  double? stressZ = -1,
  double? spo2Mean = 96,
}) => dayScore(
  sleepScore: sleepScore,
  steps: steps,
  stepGoal: 8000,
  intensityMinutes: intensityMinutes,
  hrv: baselines ? z(1) : null,
  restingHeartRate: baselines ? z(-1) : null,
  stress: stressZ == null ? null : z(stressZ),
  spo2Mean: spo2Mean,
);

DayScoreHistory historyOf(
  ScoreResult<DayScoreFactor> today, {
  bool scoredBefore = true,
}) => DayScoreHistory(
  today: metricsToday,
  days: {
    if (scoredBefore) metricsToday.addDays(-1): day(),
    metricsToday: today,
  },
);

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

Future<void> pumpToday(WidgetTester tester, Set<ModuleId> modules) =>
    pumpScaled(
      tester,
      screenHost(const TodayScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: <Override>[
        ...metricsOverrides(fullDataScenario),
        moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
      ],
    );

String textOf(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

void main() {
  group('the view', () {
    test('reads points on the published scale', () {
      final scored = day(
        steps: 4000,
        stressZ: null,
        spo2Mean: null,
      ) as Scored<DayScoreFactor>;

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
        day(intensityMinutes: null, baselines: false, spo2Mean: null),
      );

      expect(lacking(day(sleepScore: null, steps: 0)).gap, DayScoreGap.night);
      expect(lacking(day(steps: 0)).gap, DayScoreGap.steps);
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

      expect(textOf(tester, DayScoreCardKeys.band), 'Recharge day');
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
