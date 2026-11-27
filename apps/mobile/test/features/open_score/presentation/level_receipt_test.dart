import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/domain/day_tag_store.dart';
import 'package:open_ring/features/open_score/domain/level_view.dart';
import 'package:open_ring/features/open_score/presentation/day_score_receipt_screen.dart';
import 'package:open_ring/features/open_score/presentation/level_chart.dart';
import 'package:open_ring/features/open_score/presentation/level_receipt_card.dart';
import 'package:open_ring/features/open_score/presentation/level_screen.dart';

import '../../../helpers/day_score_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import 'day_score_receipt_test.dart' show overridesFor;

Future<void> pump(
  WidgetTester tester,
  Widget screen,
  DayScoreHistory history, {
  Map<LocalDate, DayTag> tags = const {},
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(360, 8000),
}) => pumpScaled(
  tester,
  screenHost(screen),
  textScaler: textScaler,
  brightness: Brightness.dark,
  locale: locale,
  overrides: [
    ...overridesFor(history),
    dayTagStoreProvider.overrideWithValue(InMemoryDayTagStore(tags)),
  ],
  size: size,
);

Finder inRow(Key key, String text) => find.descendant(
  of: find.byKey(key),
  matching: find.textContaining(text, findRichText: true),
);

String caption(WidgetTester tester, Key key) =>
    switch (tester.widget(find.byKey(key))) {
      final CaptionText text => text.text,
      final BodyText text => text.text,
      final other => throw StateError('no text in ${other.runtimeType}'),
    };

String one(double value) => value.toStringAsFixed(1);

String signed(double value) =>
    '${value < 0 ? '−' : '+'}${value.abs().toStringAsFixed(2)}';

void main() {
  final history = mixedHistory();
  final track = closedLevelTrack(history, const {});

  group('the Level on the receipt', () {
    testWidgets('a closed day shows its line, its effect and the math', (
      tester,
    ) async {
      final date = metricsToday.addDays(-1);
      final step = track.on(date)!;
      final score = history.scoredOn(date)!.value;
      await pump(tester, DayScoreReceiptScreen(day: date), history);

      expect(inRow(LevelReceiptKeys.line, one(step.before!)), findsOneWidget);
      expect(inRow(LevelReceiptKeys.score, '$score'), findsOneWidget);
      expect(inRow(LevelReceiptKeys.score, 'below the line'), findsOneWidget);
      expect(
        inRow(LevelReceiptKeys.effect, signed(step.effect!)),
        findsOneWidget,
      );
      expect(
        caption(tester, LevelReceiptKeys.math),
        '${one(step.before!)} + 3.5% × ($score − ${one(step.before!)}) '
        '= ${one(step.after!)}',
      );
    });

    testWidgets('today is worked out as if it closed now', (tester) async {
      final level = track.level!;
      await pump(tester, const DayScoreReceiptScreen(), history);

      expect(inRow(LevelReceiptKeys.line, one(level)), findsOneWidget);
      expect(
        caption(tester, LevelReceiptKeys.math),
        '${one(level)} + 3.5% × (94 − ${one(level)}) = '
        '${one(levelAfter(level, 94))}, if the day closes like this.',
      );
    });

    testWidgets('a tagged day has no effect', (tester) async {
      final date = metricsToday.addDays(-3);
      await pump(
        tester,
        DayScoreReceiptScreen(day: date),
        history,
        tags: {date: DayTag.sick},
      );

      expect(inRow(LevelReceiptKeys.effect, 'none'), findsOneWidget);
      expect(find.byKey(LevelReceiptKeys.score), findsNothing);
      expect(
        caption(tester, LevelReceiptKeys.note),
        'Day tagged as Sick. The score stays here, but it does not enter '
        'the Level.',
      );
    });

    testWidgets('a day without a score has no effect', (tester) async {
      await pump(
        tester,
        DayScoreReceiptScreen(day: metricsToday.addDays(-2)),
        history,
      );

      expect(inRow(LevelReceiptKeys.effect, 'none'), findsOneWidget);
      expect(
        caption(tester, LevelReceiptKeys.note),
        'A day without a score does not move the Level.',
      );
    });

    testWidgets('a day the Level started from has no line', (tester) async {
      await pump(
        tester,
        DayScoreReceiptScreen(day: metricsToday.addDays(-30)),
        history,
      );

      expect(find.byKey(LevelReceiptKeys.line), findsNothing);
      expect(
        caption(tester, LevelReceiptKeys.note),
        'This day has no line: it is one of the days the Level started from.',
      );
    });

    testWidgets('before the Level exists it says how far along it is', (
      tester,
    ) async {
      await pump(tester, const DayScoreReceiptScreen(), mixedHistory(days: 10));

      expect(
        caption(tester, LevelReceiptKeys.note),
        'The Level is still forming: 8 of 14 days with a score.',
      );
    });

    for (final locale in const [Locale('de'), Locale('ru'), Locale('ja')]) {
      testWidgets('fits a narrow phone at twice the text size in $locale', (
        tester,
      ) async {
        await pump(
          tester,
          DayScoreReceiptScreen(day: metricsToday.addDays(-1)),
          history,
          locale: locale,
          textScaler: const TextScaler.linear(2),
          size: const Size(320, 16000),
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(LevelReceiptKeys.card), findsOneWidget);
      });
    }
  });

  group('the Level chart', () {
    test('lists 28 days and today with the line of each', () {
      final weak = metricsToday.addDays(-3);
      final days = levelChartDays(history, closedLevelTrack(history, {weak}), {
        weak,
      });

      expect(days.length, levelAccountDays + 1);
      expect(days.last.dot, LevelDot.today);
      expect(days.last.score, 94);
      expect(days.last.line, closedLevelTrack(history, {weak}).level);
      expect(days[days.length - 2].dot, LevelDot.partial);
      expect(days[days.length - 3].dot, LevelDot.none);
      expect(days[days.length - 3].score, isNull);
      expect(days[days.length - 4].dot, LevelDot.tagged);
      expect(days[days.length - 5].dot, LevelDot.full);
      expect(days.first.line, isNull);
      expect(days.where((day) => day.line != null).length, 26);
    });

    testWidgets('is drawn on the Level screen and fits large text', (
      tester,
    ) async {
      await pump(
        tester,
        const LevelScreen(),
        history,
        locale: const Locale('de'),
        textScaler: const TextScaler.linear(2),
        size: const Size(320, 16000),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(LevelChartKeys.chart), findsOneWidget);
    });

    testWidgets('is not drawn while the Level is forming', (tester) async {
      await pump(tester, const LevelScreen(), mixedHistory(days: 10));

      expect(find.byKey(LevelChartKeys.chart), findsNothing);
    });
  });
}
