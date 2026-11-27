import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/celebration_providers.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/application/week_goal_providers.dart';
import 'package:open_ring/features/open_score/domain/celebration_store.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/open_score/domain/day_tag_store.dart';
import 'package:open_ring/features/open_score/domain/week_goal_store.dart';
import 'package:open_ring/features/open_score/presentation/day_score_card.dart';
import 'package:open_ring/features/open_score/presentation/level_celebration_card.dart';
import 'package:open_ring/features/open_score/presentation/level_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/day_score_fakes.dart';
import '../../../helpers/layout_harness.dart';
import 'day_score_receipt_test.dart' show overridesFor;

const sunday = LocalDate(2026, 11, 15);

// Seen from Sunday: Monday, Thursday, Friday and Saturday on the line,
// Tuesday below, Wednesday without a score. [yesterday] replaces Saturday.
DayScoreHistory weekHistory({DayScoreInputs? yesterday, int days = 40}) =>
    DayScoreHistory(
      today: sunday,
      days: {
        for (var age = days - 1; age >= 0; age--)
          sunday.addDays(-age): switch (age) {
            5 => day(sleepScore: 60),
            4 => day(sleepScore: null),
            1 => yesterday ?? day(),
            _ => day(),
          },
      },
    );

Future<InMemoryCelebrationStore> pump(
  WidgetTester tester,
  DayScoreHistory history, {
  required int goal,
  String? closed,
  Set<ModuleId> modules = const {ModuleId.openScore},
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(360, 8000),
}) async {
  final store = InMemoryCelebrationStore(closed);
  final router = GoRouter(
    initialLocation: '/today',
    routes: [
      GoRoute(
        path: '/today',
        builder: (_, _) => const Scaffold(
          body: SingleChildScrollView(child: DayScoreCardSlot()),
        ),
        routes: [
          GoRoute(
            path: 'day-score',
            builder: (_, _) => const SizedBox(),
            routes: [
              GoRoute(path: 'level', builder: (_, _) => const LevelScreen()),
            ],
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
    textScaler: textScaler,
    brightness: Brightness.dark,
    locale: locale,
    overrides: [
      ...overridesFor(history, modules: modules),
      dayTagStoreProvider.overrideWithValue(InMemoryDayTagStore()),
      weekGoalStoreProvider.overrideWithValue(InMemoryWeekGoalStore(goal)),
      celebrationStoreProvider.overrideWithValue(store),
    ],
    size: size,
  );
  await tester.pumpAndSettle();
  return store;
}

String title(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(LevelCelebrationKeys.title)).data!;

void main() {
  testWidgets('nothing shows on an ordinary morning', (tester) async {
    await pump(tester, weekHistory(), goal: 3);

    expect(find.byKey(LevelCelebrationKeys.card), findsNothing);
    expect(find.byType(DayScoreCard), findsOneWidget);
  });

  testWidgets('a goal met yesterday is celebrated', (tester) async {
    await pump(tester, weekHistory(), goal: 4);

    expect(title(tester), 'Weekly goal met');
    expect(
      find.text('Goal of 4 days on the line or above, completed yesterday.'),
      findsOneWidget,
    );
    expect(find.textContaining('Best day'), findsNothing);
    expect(find.textContaining('Highest Level'), findsNothing);
  });

  testWidgets('a new best day is celebrated with the one it beat', (
    tester,
  ) async {
    await pump(tester, weekHistory(yesterday: day(sleepScore: 100)), goal: 7);

    expect(title(tester), 'New personal best');
    expect(
      find.text('Best day: 100, yesterday. The previous best was 94 (Oct 7).'),
      findsOneWidget,
    );
    expect(find.textContaining('Highest Level'), findsNothing);
    expect(find.textContaining('days on the line'), findsNothing);
  });

  testWidgets('a new best day and a new highest Level share one card', (
    tester,
  ) async {
    final history = DayScoreHistory(
      today: sunday,
      days: {
        for (var age = 39; age >= 0; age--)
          sunday.addDays(-age): age == 1 ? day() : day(sleepScore: 60),
      },
    );
    await pump(tester, history, goal: 7);

    expect(title(tester), 'New personal best');
    expect(
      find.text('Best day: 94, yesterday. The previous best was 88 (Oct 7).'),
      findsOneWidget,
    );
    expect(
      find.text('Highest Level: 88.2. The previous one was 88.0 (Oct 20).'),
      findsOneWidget,
    );
  });

  testWidgets('a met goal and a best become one card', (tester) async {
    await pump(tester, weekHistory(yesterday: day(sleepScore: 100)), goal: 4);

    expect(title(tester), 'Week met and a new best');
    expect(find.byKey(LevelCelebrationKeys.card), findsOneWidget);
    expect(find.textContaining('days on the line'), findsOneWidget);
    expect(find.textContaining('Best day: 100'), findsOneWidget);
  });

  testWidgets('closing hides it for the day and remembers the day', (
    tester,
  ) async {
    final store = await pump(tester, weekHistory(), goal: 4);

    await tester.tap(find.byKey(LevelCelebrationKeys.close));
    await tester.pumpAndSettle();

    expect(find.byKey(LevelCelebrationKeys.card), findsNothing);
    expect(store.closed, '2026-11-15');
  });

  testWidgets('a card closed today stays closed', (tester) async {
    await pump(tester, weekHistory(), goal: 4, closed: '2026-11-15');

    expect(find.byKey(LevelCelebrationKeys.card), findsNothing);
  });

  testWidgets('a card closed on an earlier day does not hide a new one', (
    tester,
  ) async {
    await pump(tester, weekHistory(), goal: 4, closed: '2026-11-08');

    expect(find.byKey(LevelCelebrationKeys.card), findsOneWidget);
  });

  testWidgets('nothing shows before the Level exists', (tester) async {
    await pump(
      tester,
      weekHistory(yesterday: day(sleepScore: 100), days: 10),
      goal: 3,
    );

    expect(find.byKey(LevelCelebrationKeys.card), findsNothing);
  });

  testWidgets('nothing shows with the module off', (tester) async {
    await pump(tester, weekHistory(), goal: 4, modules: const {});

    expect(find.byKey(LevelCelebrationKeys.card), findsNothing);
  });

  testWidgets('the link opens the Level screen', (tester) async {
    await pump(tester, weekHistory(), goal: 4);

    await tester.tap(find.byKey(LevelCelebrationKeys.open));
    await tester.pumpAndSettle();

    expect(find.byType(LevelScreen), findsOneWidget);
  });

  for (final locale in const [Locale('de'), Locale('ru'), Locale('ja')]) {
    testWidgets('fits a narrow phone at twice the text size in $locale', (
      tester,
    ) async {
      await pump(
        tester,
        weekHistory(yesterday: day(sleepScore: 100)),
        goal: 4,
        locale: locale,
        textScaler: const TextScaler.linear(2),
        size: const Size(320, 12000),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(LevelCelebrationKeys.card), findsOneWidget);
    });
  }
}
