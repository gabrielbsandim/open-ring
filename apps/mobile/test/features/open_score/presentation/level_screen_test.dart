import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/domain/day_tag_store.dart';
import 'package:open_ring/features/open_score/domain/level_view.dart';
import 'package:open_ring/features/open_score/presentation/day_score_card.dart';
import 'package:open_ring/features/open_score/presentation/day_score_receipt_screen.dart';
import 'package:open_ring/features/open_score/presentation/level_block.dart';
import 'package:open_ring/features/open_score/presentation/level_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/day_score_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import 'day_score_receipt_test.dart' show overridesFor;

List<Override> _overrides(
  DayScoreHistory history,
  Map<LocalDate, DayTag> tags, {
  Set<ModuleId> modules = const {ModuleId.openScore},
}) => [
  ...overridesFor(history, modules: modules),
  dayTagStoreProvider.overrideWithValue(InMemoryDayTagStore(tags)),
];

GoRouter _router(String at) => GoRouter(
  initialLocation: at,
  routes: [
    GoRoute(
      path: '/today',
      builder: (_, _) =>
          const Scaffold(body: SingleChildScrollView(child: DayScoreCard())),
      routes: [
        GoRoute(
          path: 'day-score',
          builder: (_, state) => DayScoreReceiptScreen(
            day: LocalDate.tryParse(state.uri.queryParameters['day']),
          ),
          routes: [
            GoRoute(path: 'level', builder: (_, _) => const LevelScreen()),
          ],
        ),
      ],
    ),
  ],
);

Future<GoRouter> pumpAt(
  WidgetTester tester,
  String at,
  DayScoreHistory history, {
  Map<LocalDate, DayTag> tags = const {},
  Set<ModuleId> modules = const {ModuleId.openScore},
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(360, 6000),
}) async {
  final router = _router(at);
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
    overrides: _overrides(history, tags, modules: modules),
    size: size,
  );
  return router;
}

String text(WidgetTester tester, Key key) =>
    switch (tester.widget(find.byKey(key))) {
      final Text text => text.data!,
      final CaptionText text => text.text,
      final BodyText text => text.text,
      final other => throw StateError('no text in ${other.runtimeType}'),
    };

String one(double value) => value.toStringAsFixed(1);

void main() {
  final history = mixedHistory();
  final track = closedLevelTrack(history, const {});
  final level = track.level!;

  group('the Level screen', () {
    testWidgets('shows the Level and how it moved in 28 days', (tester) async {
      final long = mixedHistory(days: 60);
      final track = closedLevelTrack(long, const {});
      await pumpAt(tester, AppPaths.dayScoreLevel, long);

      final then = track.on(metricsToday.addDays(-29))!.after!;
      expect(text(tester, LevelKeys.value), one(track.level!));
      expect(text(tester, LevelKeys.change), contains('in 28 days'));
      expect(text(tester, LevelKeys.was), 'was ${one(then)} on Oct 12');
      expect(find.byKey(LevelKeys.forming), findsNothing);
    });

    testWidgets('works out what today would do', (tester) async {
      await pumpAt(tester, AppPaths.dayScoreLevel, history);

      final after = levelAfter(level, 94);
      expect(
        find.descendant(
          of: find.byKey(LevelKeys.todayMath),
          matching: find.text(
            '${one(level)} + 3.5% × (94 − ${one(level)}) = ${one(after)}',
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(LevelKeys.tagged), findsNothing);
    });

    testWidgets('lists a week of the account and opens to all of it', (
      tester,
    ) async {
      await pumpAt(tester, AppPaths.dayScoreLevel, history);

      expect(
        text(tester, LevelKeys.counted),
        '27 of 28 days counted. Left out: without a score: 1.',
      );
      expect(find.byKey(LevelKeys.row(metricsToday.addDays(-7))), findsOne);
      expect(find.byKey(LevelKeys.row(metricsToday.addDays(-8))), findsNothing);
      expect(find.text('no score: not counted'), findsOneWidget);

      await tester.tap(find.byKey(LevelKeys.more));
      await tester.pumpAndSettle();

      expect(find.byKey(LevelKeys.row(metricsToday.addDays(-28))), findsOne);
      expect(
        find.byKey(LevelKeys.row(metricsToday.addDays(-29))),
        findsNothing,
      );
      expect(find.text('Show only 7 days'), findsOneWidget);
    });

    testWidgets('a tagged day is listed as not counted', (tester) async {
      final weak = metricsToday.addDays(-3);
      final score = history.scoredOn(weak)!.value;
      await pumpAt(
        tester,
        AppPaths.dayScoreLevel,
        history,
        tags: {weak: DayTag.sick},
      );

      expect(
        text(tester, LevelKeys.counted),
        '26 of 28 days counted. Left out: tagged: 1, without a score: 1.',
      );
      expect(find.text('Sick, score $score: not counted'), findsOneWidget);
      expect(
        text(tester, LevelKeys.value),
        one(closedLevelTrack(history, {weak}).level!),
      );
    });

    testWidgets('a tagged today says the Level stays', (tester) async {
      await pumpAt(
        tester,
        AppPaths.dayScoreLevel,
        history,
        tags: {metricsToday: DayTag.travel},
      );

      expect(find.byKey(LevelKeys.today), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(LevelKeys.tagged),
          matching: find.text(
            'Today is tagged as Travel and does not count. The Level stays '
            'at ${one(level)}.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the weight note counts only the days that carry a weight', (
      tester,
    ) async {
      final formed = mixedHistory(days: levelSeedDays + 6);
      final track = closedLevelTrack(formed, const {});
      await pumpAt(tester, AppPaths.dayScoreLevel, formed);

      expect(track.level, isNotNull);
      expect(track.weights.length, 4);
      expect(text(tester, LevelKeys.weights), contains('The 4 days listed'));
      expect(find.textContaining(': in the starting mean'), findsWidgets);
    });

    testWidgets('a Level that has just formed has no weight note', (
      tester,
    ) async {
      final formed = DayScoreHistory(
        today: metricsToday,
        days: {
          for (var age = levelSeedDays; age >= 0; age--)
            metricsToday.addDays(-age): day(),
        },
      );
      await pumpAt(tester, AppPaths.dayScoreLevel, formed);

      expect(text(tester, LevelKeys.value), '94.0');
      expect(find.byKey(LevelKeys.weights), findsNothing);
    });

    testWidgets('a row opens the receipt of its day', (tester) async {
      final router = await pumpAt(tester, AppPaths.dayScoreLevel, history);
      final day = metricsToday.addDays(-4);

      await tester.tap(find.byKey(LevelKeys.row(day)));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        AppPaths.dayScoreOn(day.iso),
      );
    });

    testWidgets('before the seed days it says how many are left', (
      tester,
    ) async {
      await pumpAt(tester, AppPaths.dayScoreLevel, mixedHistory(days: 10));

      expect(find.byKey(LevelKeys.forming), findsOneWidget);
      expect(find.text('Days left for your Level: 6'), findsOneWidget);
      expect(find.byKey(LevelKeys.account), findsNothing);
      expect(find.byKey(LevelKeys.value), findsNothing);
    });

    testWidgets('a short history has no 28 day comparison', (tester) async {
      await pumpAt(tester, AppPaths.dayScoreLevel, mixedHistory(days: 25));

      expect(text(tester, LevelKeys.change), 'First days');
      expect(find.byKey(LevelKeys.was), findsNothing);
    });

    testWidgets('shows nothing while Open Score is off', (tester) async {
      await pumpAt(tester, AppPaths.dayScoreLevel, history, modules: const {});

      expect(find.byKey(LevelKeys.value), findsNothing);
      expect(find.byKey(LevelKeys.forming), findsNothing);
    });

    for (final locale in const [Locale('de'), Locale('ru'), Locale('ja')]) {
      testWidgets('fits a narrow phone at twice the text size in $locale', (
        tester,
      ) async {
        await pumpAt(
          tester,
          AppPaths.dayScoreLevel,
          history,
          tags: {metricsToday.addDays(-3): DayTag.rest},
          locale: locale,
          textScaler: const TextScaler.linear(2),
          size: const Size(320, 12000),
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(LevelKeys.more));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the Level on the Today card', () {
    testWidgets('says where today stands and opens the Level screen', (
      tester,
    ) async {
      final router = await pumpAt(tester, '/today', history);

      expect(text(tester, LevelBlockKeys.title), 'Above your line');
      expect(text(tester, LevelBlockKeys.value), 'Level ${one(level)}');
      expect(
        text(tester, LevelBlockKeys.caption),
        'Today is ${one(94 - level)} above. Closing like this, the Level '
        'rises to ${one(levelAfter(level, 94))}.',
      );
      expect(find.byKey(LevelBlockKeys.gauge), findsOneWidget);

      await tester.tap(find.byKey(LevelBlockKeys.block));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        AppPaths.dayScoreLevel,
      );
    });

    testWidgets('a tagged today does not count', (tester) async {
      await pumpAt(
        tester,
        '/today',
        history,
        tags: {metricsToday: DayTag.sick},
      );

      expect(text(tester, LevelBlockKeys.title), 'Today does not count');
      expect(find.byKey(LevelBlockKeys.gauge), findsNothing);
      expect(
        text(tester, LevelBlockKeys.caption),
        'A tagged day does not move the Level: it stays at ${one(level)}.',
      );
    });

    testWidgets('before the seed days it counts them', (tester) async {
      await pumpAt(tester, '/today', mixedHistory(days: 10));

      expect(text(tester, LevelBlockKeys.title), 'Days left for your Level: 6');
      expect(text(tester, LevelBlockKeys.value), '8 of 14');
      expect(find.byKey(LevelBlockKeys.gauge), findsNothing);
    });

    test('the gauge keeps a far score inside the bar', () {
      expect(const LevelGauge(score: 100, line: 40).position, 0.97);
      expect(const LevelGauge(score: 10, line: 90).position, 0.03);
      expect(const LevelGauge(score: 80, line: 80).position, 0.5);
      expect(const LevelGauge(score: 90, line: 80).position, 0.75);
    });

    for (final locale in const [Locale('de'), Locale('ru'), Locale('ja')]) {
      testWidgets('fits a narrow phone at twice the text size in $locale', (
        tester,
      ) async {
        await pumpAt(
          tester,
          '/today',
          history,
          locale: locale,
          textScaler: const TextScaler.linear(2),
          size: const Size(320, 4000),
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(LevelBlockKeys.block), findsOneWidget);
      });
    }
  });
}
