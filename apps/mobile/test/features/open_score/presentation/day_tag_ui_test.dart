import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/domain/day_tag_store.dart';
import 'package:open_ring/features/open_score/presentation/day_score_card.dart';
import 'package:open_ring/features/open_score/presentation/day_score_history_screen.dart';
import 'package:open_ring/features/open_score/presentation/day_score_receipt_screen.dart';
import 'package:open_ring/features/open_score/presentation/day_tag_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/day_score_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import 'day_score_history_test.dart' show historyRouter;
import 'day_score_receipt_test.dart' show overridesFor;

List<Override> tagged(DayScoreHistory history, DayTagStore store) => [
  ...overridesFor(history),
  dayTagStoreProvider.overrideWithValue(store),
];

Future<void> pumpCard(
  WidgetTester tester,
  DayTagStore store, {
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Size size = phoneSize,
}) => pumpScaled(
  tester,
  screenHost(
    const Scaffold(body: SingleChildScrollView(child: DayScoreCard())),
  ),
  textScaler: textScaler,
  brightness: Brightness.dark,
  locale: locale,
  overrides: tagged(historyOf(day()), store),
  size: size,
);

Future<void> pumpReceipt(
  WidgetTester tester,
  DayScoreHistory history,
  DayTagStore store, {
  LocalDate? on,
}) => pumpScaled(
  tester,
  screenHost(DayScoreReceiptScreen(day: on)),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  overrides: tagged(history, store),
  size: const Size(360, 6000),
);

Future<void> pumpHistory(
  WidgetTester tester,
  DayScoreHistory history,
  DayTagStore store,
) async {
  final router = historyRouter();
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
    overrides: tagged(history, store),
    size: const Size(360, 6000),
  );
}

String caption(WidgetTester tester, Key key) =>
    tester.widget<CaptionText>(find.byKey(key)).text;

String linkText(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(DayScoreCardKeys.tag),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  group('the Today card', () {
    testWidgets('offers the tag and saves the one picked', (tester) async {
      final store = InMemoryDayTagStore();
      await pumpCard(tester, store);

      expect(linkText(tester), 'Unusual day? Tag it as sick, travel or rest');
      expect(find.byKey(DayScoreCardKeys.tagged), findsNothing);

      await tester.tap(find.byKey(DayScoreCardKeys.tag));
      await tester.pumpAndSettle();
      expect(find.text('Tag today'), findsOneWidget);
      await tester.tap(find.byKey(DayTagSheetKeys.option(DayTag.sick)));
      await tester.pumpAndSettle();

      expect(await store.all(), {metricsToday: DayTag.sick});
      expect(find.text('Tagged as Sick.'), findsOneWidget);
      expect(
        caption(tester, DayScoreCardKeys.tagged),
        'Tagged as Sick. This day stays out of the Level, the weekly '
        'goal, the bests and the averages.',
      );
      expect(linkText(tester), 'Change tag');
      expect(find.byType(DayTagChip), findsOneWidget);
    });

    testWidgets('undo puts the earlier tag back', (tester) async {
      final store = InMemoryDayTagStore({metricsToday: DayTag.travel});
      await pumpCard(tester, store);

      await tester.tap(find.byKey(DayScoreCardKeys.tag));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DayTagSheetKeys.none));
      await tester.pumpAndSettle();
      expect(await store.all(), isEmpty);
      expect(find.text('Tag removed.'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(await store.all(), {metricsToday: DayTag.travel});
      expect(
        caption(tester, DayScoreCardKeys.tagged),
        'Tagged as Travel. This day stays out of the Level, the weekly '
        'goal, the bests and the averages.',
      );
    });

    testWidgets('picking the same tag or closing changes nothing', (
      tester,
    ) async {
      final store = InMemoryDayTagStore({metricsToday: DayTag.rest});
      await pumpCard(tester, store);

      await tester.tap(find.byKey(DayScoreCardKeys.tag));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DayTagSheetKeys.option(DayTag.rest)));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.byKey(DayScoreCardKeys.tag));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DayTagSheetKeys.close));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(await store.all(), {metricsToday: DayTag.rest});
    });

    testWidgets('the headline reads the tag aloud', (tester) async {
      await pumpCard(tester, InMemoryDayTagStore({metricsToday: DayTag.sick}));

      expect(
        find.bySemanticsLabel(
          RegExp(r'Day Score 94 of 100, .*\. Tagged as Sick\. This day'),
        ),
        findsOneWidget,
      );
    });

    for (final locale in const [Locale('de'), Locale('ru'), Locale('ja')]) {
      testWidgets('fits a narrow phone at twice the text size in $locale', (
        tester,
      ) async {
        await pumpCard(
          tester,
          InMemoryDayTagStore({metricsToday: DayTag.travel}),
          locale: locale,
          textScaler: const TextScaler.linear(2),
          size: const Size(320, 640),
        );
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.byKey(DayScoreCardKeys.tag));
        await tester.tap(find.byKey(DayScoreCardKeys.tag));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(DayTagSheetKeys.none), findsOneWidget);
      });
    }
  });

  group('the receipt', () {
    testWidgets('has a row that names the tag and opens the sheet', (
      tester,
    ) async {
      final yesterday = metricsToday.addDays(-1);
      final store = InMemoryDayTagStore();
      await pumpReceipt(tester, historyOf(day()), store, on: yesterday);

      expect(
        find.text('None. Use it on a sick, travel or rest day.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(DayScoreReceiptKeys.tag));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DayTagSheetKeys.option(DayTag.travel)));
      await tester.pumpAndSettle();

      expect(await store.all(), {yesterday: DayTag.travel});
      expect(find.text('Travel. Tap to change or remove.'), findsOneWidget);
      expect(find.byType(DayTagChip), findsOneWidget);
    });

    testWidgets('locks the tag of a day older than the window', (tester) async {
      final old = metricsToday.addDays(-dayTagEditableDays);
      await pumpReceipt(
        tester,
        mixedHistory(),
        InMemoryDayTagStore({old: DayTag.sick}),
        on: old,
      );

      expect(find.byKey(DayScoreReceiptKeys.tag), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(DayScoreReceiptKeys.tagLocked),
          matching: find.text(
            'Day tagged as Sick. The tag can only be changed for today and '
            'the 6 days before.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the last day of the window can still be tagged', (
      tester,
    ) async {
      await pumpReceipt(
        tester,
        mixedHistory(),
        InMemoryDayTagStore(),
        on: metricsToday.addDays(1 - dayTagEditableDays),
      );

      expect(find.byKey(DayScoreReceiptKeys.tag), findsOneWidget);
      expect(find.byKey(DayScoreReceiptKeys.tagLocked), findsNothing);
    });
  });

  group('the history', () {
    testWidgets('the calendar reads a tagged day as set aside', (tester) async {
      final weak = metricsToday.addDays(-3);
      final blank = metricsToday.addDays(-2);
      await pumpHistory(
        tester,
        mixedHistory(),
        InMemoryDayTagStore({weak: DayTag.sick, blank: DayTag.rest}),
      );

      final score = mixedHistory().scoredOn(weak)!.value;
      expect(
        find.bySemanticsLabel(
          RegExp(', tagged as Sick, does not count, score $score\$'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r', tagged as Rest, no score$')),
        findsOneWidget,
      );
    });

    testWidgets('the average leaves tagged days out', (tester) async {
      final history = mixedHistory();
      final weak = metricsToday.addDays(-3);
      final all = history.fullAverage(30)!;
      final without = history.fullAverage(30, excluded: {weak})!;
      expect(without.count, all.count - 1);

      await pumpHistory(
        tester,
        history,
        InMemoryDayTagStore({weak: DayTag.sick}),
      );
      await tester.tap(find.text('30 days'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(DayScoreHistoryKeys.average),
          matching: find.text(
            'Average of the ${without.count} closed days with full coverage',
          ),
        ),
        findsOneWidget,
      );
    });
  });
}
