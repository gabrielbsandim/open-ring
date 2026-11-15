import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/application/week_goal_providers.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/domain/day_tag_store.dart';
import 'package:open_ring/features/open_score/domain/week_goal_store.dart';
import 'package:open_ring/features/open_score/presentation/level_goal_cards.dart';
import 'package:open_ring/features/open_score/presentation/level_screen.dart';

import '../../../helpers/day_score_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import 'day_score_receipt_test.dart' show overridesFor;

const sunday = LocalDate(2026, 11, 15);

// Monday on the line, Tuesday below, Wednesday without a score, then three
// days on the line, seen from Sunday.
DayScoreHistory weekHistory() => DayScoreHistory(
  today: sunday,
  days: {
    for (var age = 39; age >= 0; age--)
      sunday.addDays(-age): switch (age) {
        5 => day(sleepScore: 60),
        4 => day(sleepScore: null),
        _ => day(),
      },
  },
);

Future<InMemoryWeekGoalStore> pump(
  WidgetTester tester,
  DayScoreHistory history, {
  int? goal,
  Map<LocalDate, DayTag> tags = const {},
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(360, 8000),
}) async {
  final store = InMemoryWeekGoalStore(goal);
  await pumpScaled(
    tester,
    screenHost(const LevelScreen()),
    textScaler: textScaler,
    brightness: Brightness.dark,
    locale: locale,
    overrides: [
      ...overridesFor(history),
      dayTagStoreProvider.overrideWithValue(InMemoryDayTagStore(tags)),
      weekGoalStoreProvider.overrideWithValue(store),
    ],
    size: size,
  );
  return store;
}

String text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

String label(WidgetTester tester, LocalDate date) =>
    tester.getSemantics(find.byKey(LevelGoalKeys.day(date))).label;

Finder inside(Key key, String value) =>
    find.descendant(of: find.byKey(key), matching: find.text(value));

void main() {
  group('the weekly goal', () {
    testWidgets('starts at four days and counts closed days only', (
      tester,
    ) async {
      await pump(tester, mixedHistory());

      expect(text(tester, LevelGoalKeys.count), '0');
      expect(text(tester, LevelGoalKeys.goal), '4');
      expect(
        text(tester, LevelGoalKeys.message),
        'Days still needed: 4. Today counts once it closes, at midnight.',
      );
      expect(inside(LevelGoalKeys.week, 'Nov 9 to Nov 15'), findsOneWidget);
      expect(label(tester, metricsToday.addDays(-1)), 'Mon: below the line');
      expect(label(tester, metricsToday), 'Tue: in progress');
      expect(label(tester, metricsToday.addDays(1)), 'Wed: still to come');
    });

    testWidgets('says which day completed it', (tester) async {
      await pump(
        tester,
        weekHistory(),
        goal: 3,
        tags: {sunday.addDays(-3): DayTag.rest},
      );

      expect(text(tester, LevelGoalKeys.count), '3');
      expect(
        text(tester, LevelGoalKeys.message),
        'Goal met (Sat, Nov 14). The rest of the week is yours.',
      );
      expect(label(tester, sunday.addDays(-6)), 'Mon: on the line or above');
      expect(label(tester, sunday.addDays(-5)), 'Tue: below the line');
      expect(label(tester, sunday.addDays(-4)), 'Wed: no score');
      expect(label(tester, sunday.addDays(-3)), 'Thu: tagged, does not count');
      expect(label(tester, sunday), 'Sun: in progress');
    });

    testWidgets('a tagged today is not promised to count', (tester) async {
      await pump(tester, mixedHistory(), tags: {metricsToday: DayTag.sick});

      expect(label(tester, metricsToday), 'Tue: tagged, does not count');
      expect(text(tester, LevelGoalKeys.message), 'Days still needed: 4.');
    });

    testWidgets('says so when the week can no longer reach it', (tester) async {
      await pump(tester, weekHistory(), goal: 6);

      expect(text(tester, LevelGoalKeys.count), '4');
      expect(
        text(tester, LevelGoalKeys.message),
        'This week will not reach the goal, and that is fine: nothing is '
        'lost, and there is no streak to break.',
      );
    });

    testWidgets('the stepper saves the goal and stops at the limits', (
      tester,
    ) async {
      final store = await pump(tester, weekHistory(), goal: 6);

      await tester.tap(find.byKey(LevelGoalKeys.more));
      await tester.pumpAndSettle();

      expect(store.goal, 7);
      expect(text(tester, LevelGoalKeys.goal), '7');
      expect(
        tester.widget<IconButton>(find.byKey(LevelGoalKeys.more)).onPressed,
        isNull,
      );

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(LevelGoalKeys.less));
        await tester.pumpAndSettle();
      }

      expect(store.goal, 3);
      expect(
        text(tester, LevelGoalKeys.message),
        'Goal met (Fri, Nov 13). The rest of the week is yours.',
      );
      expect(
        tester.widget<IconButton>(find.byKey(LevelGoalKeys.less)).onPressed,
        isNull,
      );
    });

    testWidgets('a stored goal outside the range is brought back in', (
      tester,
    ) async {
      await pump(tester, mixedHistory(), goal: 12);

      expect(text(tester, LevelGoalKeys.goal), '7');
    });

    testWidgets('waits for the Level to exist', (tester) async {
      await pump(tester, mixedHistory(days: 10));

      expect(find.byKey(LevelGoalKeys.forming), findsOneWidget);
      expect(find.byKey(LevelGoalKeys.week), findsNothing);
      expect(find.byKey(LevelGoalKeys.bests), findsNothing);
    });
  });

  group('the personal bests', () {
    testWidgets('show the best day, the best week and the highest Level', (
      tester,
    ) async {
      await pump(tester, mixedHistory());

      expect(inside(LevelGoalKeys.bestDay, '94'), findsOneWidget);
      expect(inside(LevelGoalKeys.bestDay, 'Fri, Oct 2'), findsOneWidget);
      expect(inside(LevelGoalKeys.bestWeek, '94'), findsOneWidget);
      expect(
        inside(LevelGoalKeys.bestWeek, 'Mean of the scores, Oct 5 to Oct 11'),
        findsOneWidget,
      );
      expect(inside(LevelGoalKeys.bestLevel, '94.0'), findsOneWidget);
      expect(inside(LevelGoalKeys.bestLevel, 'Thu, Oct 15'), findsOneWidget);
      expect(
        inside(
          LevelGoalKeys.bests,
          'Bests look at the last $dayScoreHistoryDays days. Tagged days stay '
          'out.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('say what the best week still needs', (tester) async {
      final history = DayScoreHistory(
        today: sunday,
        days: {
          for (var age = 23; age >= 0; age--)
            sunday.addDays(-age): switch (age) {
              >= 17 && <= 20 || >= 10 && <= 13 => day(sleepScore: null),
              _ => day(),
            },
        },
      );
      await pump(tester, history);

      expect(
        inside(LevelGoalKeys.bestWeek, 'Needs a week with 4 counted days'),
        findsOneWidget,
      );
      expect(find.byKey(LevelGoalKeys.bestLevel), findsOneWidget);
    });
  });

  for (final locale in const [Locale('de'), Locale('ru'), Locale('ja')]) {
    testWidgets('fits a narrow phone at twice the text size in $locale', (
      tester,
    ) async {
      await pump(
        tester,
        weekHistory(),
        goal: 3,
        tags: {sunday.addDays(-3): DayTag.rest},
        locale: locale,
        textScaler: const TextScaler.linear(2),
        size: const Size(320, 20000),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(LevelGoalKeys.week), findsOneWidget);
      expect(find.byKey(LevelGoalKeys.bests), findsOneWidget);
    });
  }
}
