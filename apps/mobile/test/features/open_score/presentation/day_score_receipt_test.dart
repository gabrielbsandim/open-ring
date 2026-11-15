import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/application/day_score_view.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/open_score/presentation/day_score_card.dart';
import 'package:open_ring/features/open_score/presentation/day_score_receipt_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/day_score_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';

List<Override> overridesFor(
  DayScoreHistory? history, {
  Set<ModuleId> modules = const {ModuleId.openScore},
}) => [
  clockProvider.overrideWithValue(() => metricsNow),
  moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
  dayScoreHistoryProvider.overrideWith((ref) async {
    if (history == null) throw StateError('no database');
    return history;
  }),
];

Future<void> pumpReceipt(
  WidgetTester tester,
  DayScoreHistory? history, {
  Set<ModuleId> modules = const {ModuleId.openScore},
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
}) => pumpScaled(
  tester,
  screenHost(const DayScoreReceiptScreen()),
  textScaler: textScaler,
  brightness: Brightness.dark,
  locale: locale,
  overrides: overridesFor(history, modules: modules),
  size: const Size(360, 6000),
);

Finder within(Key key, String text) =>
    find.descendant(of: find.byKey(key), matching: find.text(text));

String textOf(WidgetTester tester, Key key) =>
    switch (tester.widget(find.byKey(key))) {
      final Text text => text.data!,
      final CaptionText text => text.text,
      final BodyText text => text.text,
      final other => throw StateError('no text in ${other.runtimeType}'),
    };

IconButton button(WidgetTester tester, Key key) =>
    tester.widget<IconButton>(find.byKey(key));

void main() {
  group('the receipt view', () {
    test('adds points on the published scale for a partial day', () {
      final receipt = DayScoreReceipt(
        day(steps: 4000, stressZ: null, spo2Mean: null),
      );

      expect(receipt.total, 24 + 7.5 + 20 + 10 + 10);
      expect(receipt.coverage, 85);
      expect(receipt.missing, [DayScoreFactor.stress, DayScoreFactor.spo2]);
      expect(receipt.open, 7.5);
      expect(receipt.gap, isNull);
      expect(receipt.scored?.value, (71.5 / 85 * 100).round());
    });

    test('keeps the points of a day that has no score', () {
      final receipt = DayScoreReceipt(day(sleepScore: null));

      expect(receipt.scored, isNull);
      expect(receipt.gap, DayScoreGap.night);
      expect(receipt.coverage, 70);
      expect(receipt.of(DayScoreFactor.steps)?.points, 15);
    });
  });

  group('the screen', () {
    testWidgets('a full day lists every factor and the total', (tester) async {
      await pumpReceipt(tester, historyOf(day()));

      expect(textOf(tester, DayScoreReceiptKeys.day), startsWith('Today, '));
      expect(
        textOf(tester, DayScoreReceiptKeys.status),
        startsWith('so far, '),
      );
      expect(within(DayScoreReceiptKeys.earned, '94 of 100'), findsOneWidget);
      expect(within(DayScoreReceiptKeys.result, '94'), findsOneWidget);
      expect(find.byKey(DayScoreReceiptKeys.leftOut), findsNothing);
      expect(find.byKey(DayScoreReceiptKeys.rescale), findsNothing);
      expect(find.byKey(DayScoreReceiptKeys.open), findsNothing);
      for (final factor in DayScoreFactor.values) {
        expect(find.byKey(DayScoreReceiptKeys.factor(factor)), findsOneWidget);
      }
      expect(
        within(
          DayScoreReceiptKeys.factor(DayScoreFactor.steps),
          'Input: 8,000 of 8,000 steps, so far',
        ),
        findsOneWidget,
      );
      expect(
        within(
          DayScoreReceiptKeys.factor(DayScoreFactor.sleep),
          'Rule: score ÷ 100. Weight: 30 points.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a partial day shows what stayed out and the rescale', (
      tester,
    ) async {
      await pumpReceipt(
        tester,
        historyOf(day(steps: 4000, stressZ: null, spo2Mean: null)),
      );

      expect(within(DayScoreReceiptKeys.earned, '71.5 of 85'), findsOneWidget);
      expect(within(DayScoreReceiptKeys.leftOut, '15 points'), findsOneWidget);
      expect(
        within(DayScoreReceiptKeys.rescale, '71.5 ÷ 85 × 100'),
        findsOneWidget,
      );
      expect(within(DayScoreReceiptKeys.result, '84'), findsOneWidget);
      expect(
        within(DayScoreReceiptKeys.factor(DayScoreFactor.stress), 'left out'),
        findsOneWidget,
      );
      expect(
        textOf(tester, DayScoreReceiptKeys.open),
        contains('up to 7.5 points from steps'),
      );
    });

    testWidgets('the rescale line divides to the score shown', (tester) async {
      await pumpReceipt(
        tester,
        historyOf(
          const DayScoreInputs(
            sleepScore: 73,
            steps: 5107,
            stepGoal: 10000,
            intensityMinutes: 0,
          ),
        ),
      );

      expect(within(DayScoreReceiptKeys.earned, '29.6 of 65'), findsOneWidget);
      expect(
        within(DayScoreReceiptKeys.rescale, '29.56 ÷ 65 × 100'),
        findsOneWidget,
      );
      expect(within(DayScoreReceiptKeys.result, '45'), findsOneWidget);
    });

    testWidgets('a day without its night says why and keeps the math', (
      tester,
    ) async {
      await pumpReceipt(tester, historyOf(day(sleepScore: null)));

      expect(find.byKey(DayScoreReceiptKeys.none), findsOneWidget);
      expect(find.text('Day without a score'), findsOneWidget);
      expect(within(DayScoreReceiptKeys.result, 'no score'), findsOneWidget);
      expect(within(DayScoreReceiptKeys.earned, '70 of 70'), findsOneWidget);
      expect(find.byKey(DayScoreReceiptKeys.minimum), findsNothing);
    });

    testWidgets('thin coverage names the minimum', (tester) async {
      await pumpReceipt(
        tester,
        historyOf(
          day(intensityMinutes: null, baselines: false, spo2Mean: null),
          scoredBefore: false,
        ),
      );

      expect(find.text('No score yet'), findsOneWidget);
      expect(
        textOf(tester, DayScoreReceiptKeys.minimum),
        'Coverage of 55 points. The minimum for a score is 60.',
      );
    });

    testWidgets('the arrows walk the days and stop at both ends', (
      tester,
    ) async {
      await pumpReceipt(tester, historyOf(day(steps: 4000)));

      expect(button(tester, DayScoreReceiptKeys.next).onPressed, isNull);

      await tester.tap(find.byKey(DayScoreReceiptKeys.previous));
      await tester.pumpAndSettle();

      expect(
        textOf(tester, DayScoreReceiptKeys.day),
        startsWith('Yesterday, '),
      );
      expect(textOf(tester, DayScoreReceiptKeys.status), 'final score');
      expect(button(tester, DayScoreReceiptKeys.previous).onPressed, isNull);
      expect(find.byKey(DayScoreReceiptKeys.open), findsNothing);
      expect(
        within(
          DayScoreReceiptKeys.factor(DayScoreFactor.steps),
          'Input: 8,000 of 8,000 steps',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(DayScoreReceiptKeys.next));
      await tester.pumpAndSettle();

      expect(textOf(tester, DayScoreReceiptKeys.day), startsWith('Today, '));
    });

    testWidgets('with Open Score off the screen shows no day', (tester) async {
      await pumpReceipt(tester, historyOf(day()), modules: const {});

      expect(find.byKey(DayScoreReceiptKeys.day), findsNothing);
      expect(find.byKey(DayScoreReceiptKeys.result), findsNothing);
    });

    testWidgets('a failed read shows the load error', (tester) async {
      await pumpReceipt(tester, null);

      expect(find.byKey(DayScoreReceiptKeys.day), findsNothing);
      expect(
        find.text(
          'Could not read your stored data. Close the app and open it again.',
        ),
        findsOneWidget,
      );
    });

    for (final MapEntry(key: name, value: history) in {
      'a full day': historyOf(day()),
      'a partial day': historyOf(
        day(steps: 4000, stressZ: null, spo2Mean: null),
      ),
      'a day without a score': historyOf(day(sleepScore: null)),
    }.entries) {
      testWidgets('$name fits at twice the text size in German', (
        tester,
      ) async {
        await pumpReceipt(
          tester,
          history,
          locale: const Locale('de'),
          textScaler: const TextScaler.linear(2),
        );

        expect(find.byKey(DayScoreReceiptKeys.result), findsOneWidget);
      });
    }
  });

  testWidgets('tapping the Today card opens the receipt', (tester) async {
    final router = GoRouter(
      initialLocation: AppTab.today.path,
      routes: [
        GoRoute(
          path: AppTab.today.path,
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(child: DayScoreCard()),
          ),
          routes: [
            GoRoute(
              path: 'day-score',
              builder: (_, _) => const DayScoreReceiptScreen(),
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
    );

    await tester.tap(find.byKey(DayScoreCardKeys.card));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppPaths.dayScore);
    expect(find.byKey(DayScoreReceiptKeys.result), findsOneWidget);
  });
}
