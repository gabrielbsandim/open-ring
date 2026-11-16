import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/open_score/application/overall_providers.dart';
import 'package:open_ring/features/open_score/domain/overall_history.dart';
import 'package:open_ring/features/open_score/presentation/overall_row.dart';
import 'package:open_ring/features/open_score/presentation/overall_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';

const monday = LocalDate(2026, 11, 9);

const full = OverallInputs(
  fitnessPercentile: 52,
  restingHeartRate: 53,
  sleepHours: 6.6,
  sleepRegularity: 66,
  weeklyMinutes: 132,
  strengthPerWeek: 1.5,
  dailySteps: 6900,
  waistToHeight: 0.49,
);

const partial = OverallInputs(
  restingHeartRate: 53,
  sleepHours: 6.6,
  sleepRegularity: 66,
  weeklyMinutes: 132,
  strengthPerWeek: 1.5,
  dailySteps: 6900,
);

const empty = OverallInputs();

OverallWeek week(LocalDate date, OverallInputs inputs) =>
    (date: date, inputs: inputs, result: inputs.score);

OverallHistory historyOf(
  OverallInputs inputs, {
  OverallInputs before = empty,
  int nights = 22,
}) {
  final current = week(monday, inputs);
  return OverallHistory(
    today: metricsToday,
    weeks: [week(monday.addDays(-7), before), current],
    current: current,
    nights: nights,
  );
}

List<Override> overridesFor(
  OverallHistory? history, {
  Set<ModuleId> modules = const {ModuleId.openScore},
  bool hidden = false,
}) => [
  clockProvider.overrideWithValue(() => metricsNow),
  moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
  numbersHiddenProvider.overrideWithValue(hidden),
  overallHistoryProvider.overrideWith((ref) async {
    if (history == null) throw StateError('no database');
    return history;
  }),
];

Future<void> pump(
  WidgetTester tester,
  Widget child,
  OverallHistory? history, {
  Set<ModuleId> modules = const {ModuleId.openScore},
  bool hidden = false,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await pumpScaled(
    tester,
    screenHost(child),
    textScaler: textScaler,
    brightness: Brightness.dark,
    locale: locale,
    overrides: overridesFor(history, modules: modules, hidden: hidden),
    size: const Size(360, 3000),
  );
  await tester.pumpAndSettle();
}

String text(WidgetTester tester, Key key) =>
    switch (tester.widget(find.byKey(key))) {
      final Text text => text.data!,
      final CaptionText text => text.text,
      final other => throw StateError('no text in ${other.runtimeType}'),
    };

const row = Scaffold(body: OverallRow());

void main() {
  group('the row on Today', () {
    testWidgets('shows the band, the update date and the number', (
      tester,
    ) async {
      await pump(tester, row, historyOf(full));

      expect(text(tester, OverallRowKeys.score), '69');
      expect(text(tester, OverallRowKeys.note), contains('Base in the making'));
      expect(text(tester, OverallRowKeys.note), contains('updated'));
    });

    testWidgets('without a score it counts the nights and has no number', (
      tester,
    ) async {
      await pump(tester, row, historyOf(empty, nights: 9));

      expect(text(tester, OverallRowKeys.note), 'Forming: 9 of 14 nights');
      expect(find.byKey(OverallRowKeys.score), findsNothing);
    });

    testWidgets('never counts more nights than it needs', (tester) async {
      await pump(tester, row, historyOf(empty, nights: 20));

      expect(text(tester, OverallRowKeys.note), 'Forming: 14 of 14 nights');
    });

    testWidgets('is absent when the history fails to load', (tester) async {
      await pump(tester, row, null);

      expect(find.byKey(OverallRowKeys.row), findsNothing);
    });
  });

  group('the screen', () {
    testWidgets('with Open Score off shows no content', (tester) async {
      await pump(
        tester,
        const OverallScreen(),
        historyOf(full),
        modules: const {},
      );

      expect(find.byKey(OverallKeys.card), findsNothing);
      expect(find.byKey(OverallKeys.forming), findsNothing);
    });

    testWidgets('a full week shows score, band and full coverage', (
      tester,
    ) async {
      await pump(tester, const OverallScreen(), historyOf(full));

      expect(text(tester, OverallKeys.score), '69');
      expect(text(tester, OverallKeys.band), 'Base in the making');
      expect(text(tester, OverallKeys.coverage), 'Full coverage');
      expect(text(tester, OverallKeys.updated), startsWith('Updated'));
      expect(text(tester, OverallKeys.updated), contains('Next update on'));
      expect(find.byKey(OverallKeys.change), findsNothing);
      for (final factor in OverallFactor.values) {
        expect(find.byKey(OverallKeys.factor(factor)), findsOneWidget);
      }
      expect(text(tester, OverallKeys.points(OverallFactor.body)), '10 of 10');
    });

    testWidgets('a missing factor is listed outside the count', (tester) async {
      await pump(tester, const OverallScreen(), historyOf(partial));

      expect(text(tester, OverallKeys.coverage), '60 of 100 points');
      expect(
        text(tester, OverallKeys.points(OverallFactor.fitness)),
        'outside the count',
      );
      expect(
        text(tester, OverallKeys.points(OverallFactor.body)),
        'outside the count',
      );
      expect(
        find.textContaining('Its 30 points leave the count'),
        findsOneWidget,
      );
    });

    testWidgets('without a score shows the forming state', (tester) async {
      await pump(tester, const OverallScreen(), historyOf(empty, nights: 9));

      expect(find.byKey(OverallKeys.forming), findsOneWidget);
      expect(find.byKey(OverallKeys.card), findsNothing);
      expect(find.textContaining('You have 9.'), findsOneWidget);
    });

    testWidgets('the body row hides its number while numbers are hidden', (
      tester,
    ) async {
      await pump(tester, const OverallScreen(), historyOf(full), hidden: true);

      expect(find.textContaining('0.49'), findsNothing);
      expect(
        find.text('From your last measurement in the Body module.'),
        findsOneWidget,
      );
    });

    testWidgets('the body row shows the ratio otherwise', (tester) async {
      await pump(tester, const OverallScreen(), historyOf(full));

      expect(find.textContaining('0.49'), findsOneWidget);
    });

    testWidgets('a change under 2 points is called noise', (tester) async {
      await pump(tester, const OverallScreen(), historyOf(full, before: full));

      expect(text(tester, OverallKeys.change), contains('noise'));
    });

    testWidgets('a larger change says by how much', (tester) async {
      const weak = OverallInputs(
        restingHeartRate: 78,
        sleepHours: 5.2,
        sleepRegularity: 52,
        weeklyMinutes: 20,
        dailySteps: 3000,
      );
      final rise =
          (full.score as Scored<OverallFactor>).value -
          (weak.score as Scored<OverallFactor>).value;

      await pump(tester, const OverallScreen(), historyOf(full, before: weak));

      expect(rise, greaterThan(20));
      expect(
        text(tester, OverallKeys.change),
        '$rise points above the week before',
      );
    });

    testWidgets('a load error shows the error text', (tester) async {
      await pump(tester, const OverallScreen(), null);

      expect(find.byKey(OverallKeys.card), findsNothing);
      expect(find.byType(BodyText), findsOneWidget);
    });
  });

  group('layout', () {
    for (final locale in AppLocales.supported) {
      testWidgets('fits at large text in $locale', (tester) async {
        await pump(
          tester,
          const OverallScreen(),
          historyOf(partial, before: full),
          locale: locale,
          textScaler: const TextScaler.linear(1.6),
        );
        await pump(
          tester,
          row,
          historyOf(full),
          locale: locale,
          textScaler: const TextScaler.linear(1.6),
        );
      });
    }
  });
}
