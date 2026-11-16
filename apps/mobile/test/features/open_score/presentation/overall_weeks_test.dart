import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/open_score/domain/overall_history.dart';
import 'package:open_ring/features/open_score/domain/overall_trend.dart';
import 'package:open_ring/features/open_score/presentation/overall_screen.dart';
import 'package:open_ring/features/open_score/presentation/overall_weeks_screen.dart';

import '../../../helpers/metrics_fakes.dart';
import 'overall_screen_test.dart'
    show empty, full, historyOf, monday, partial, pump, text, week;

const weak = OverallInputs(
  restingHeartRate: 78,
  sleepHours: 5.2,
  sleepRegularity: 52,
  weeklyMinutes: 20,
  dailySteps: 3000,
);

OverallHistory weeksOf(List<OverallInputs> inputs) {
  final weeks = [
    for (var i = 0; i < inputs.length; i++)
      week(monday.addDays(-7 * (inputs.length - 1 - i)), inputs[i]),
  ];
  return OverallHistory(
    today: metricsToday,
    weeks: weeks,
    current: weeks.last,
    nights: 22,
  );
}

int scoreOf(OverallInputs value) =>
    (value.score as Scored<OverallFactor>).value;

void main() {
  testWidgets('with Open Score off shows no content', (tester) async {
    await pump(
      tester,
      const OverallWeeksScreen(),
      weeksOf([weak, partial]),
      modules: const {},
    );

    expect(find.byKey(OverallWeeksKeys.chart), findsNothing);
    expect(find.byKey(OverallWeeksKeys.few), findsNothing);
  });

  testWidgets('with one scored Monday says how many it needs', (tester) async {
    await pump(tester, const OverallWeeksScreen(), weeksOf([empty, partial]));

    expect(find.byKey(OverallWeeksKeys.chart), findsNothing);
    expect(
      find.text('The chart starts with 2 scored Mondays. You have 1.'),
      findsOneWidget,
    );
  });

  testWidgets('shows the change, the chart and the three numbers', (
    tester,
  ) async {
    final history = weeksOf([weak, empty, partial, partial]);
    final trend = OverallTrend.of(history.weeks)!;
    await pump(tester, const OverallWeeksScreen(), history);

    expect(find.byKey(OverallWeeksKeys.chart), findsOneWidget);
    expect(
      text(tester, OverallWeeksKeys.since),
      startsWith('+${scoreOf(partial) - scoreOf(weak)} since'),
    );
    expect(
      find.descendant(
        of: find.byKey(OverallWeeksKeys.now),
        matching: find.text('${scoreOf(partial)}'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(OverallWeeksKeys.floor),
        matching: find.text('${trend.floor}'),
      ),
      findsOneWidget,
    );
    expect(trend.floor, scoreOf(weak));
    expect(
      find.descendant(
        of: find.byKey(OverallWeeksKeys.typical),
        matching: find.text('${trend.typical}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('what changed lists only factors scored in both weeks', (
    tester,
  ) async {
    await pump(tester, const OverallWeeksScreen(), weeksOf([weak, full]));

    expect(
      find.byKey(OverallWeeksKeys.change(OverallFactor.restingHeartRate)),
      findsOneWidget,
    );
    expect(
      find.byKey(OverallWeeksKeys.change(OverallFactor.body)),
      findsNothing,
    );
    expect(
      find.byKey(OverallWeeksKeys.change(OverallFactor.fitness)),
      findsNothing,
    );
  });

  testWidgets('the Body change is not listed while numbers are hidden', (
    tester,
  ) async {
    const before = OverallInputs(
      restingHeartRate: 60,
      sleepHours: 6.6,
      sleepRegularity: 66,
      weeklyMinutes: 132,
      dailySteps: 6900,
      waistToHeight: 0.58,
    );
    await pump(
      tester,
      const OverallWeeksScreen(),
      weeksOf([before, full]),
      hidden: true,
    );

    expect(
      find.byKey(OverallWeeksKeys.change(OverallFactor.body)),
      findsNothing,
    );
    expect(
      find.byKey(OverallWeeksKeys.change(OverallFactor.restingHeartRate)),
      findsOneWidget,
    );

    await pump(tester, const OverallWeeksScreen(), weeksOf([before, full]));

    expect(
      find.byKey(OverallWeeksKeys.change(OverallFactor.body)),
      findsOneWidget,
    );
  });

  testWidgets('a factor that did not move reads the same', (tester) async {
    await pump(tester, const OverallWeeksScreen(), weeksOf([partial, partial]));

    expect(
      tester
          .widget<BodyText>(
            find.byKey(OverallWeeksKeys.change(OverallFactor.sleepDuration)),
          )
          .text,
      'the same',
    );
  });

  testWidgets('the Overall screen links to the 12 weeks', (tester) async {
    await pump(tester, const OverallScreen(), historyOf(full));

    expect(find.byKey(OverallKeys.weeks), findsOneWidget);
    expect(find.text('12 weeks'), findsOneWidget);
  });

  testWidgets('a load error shows no chart', (tester) async {
    await pump(tester, const OverallWeeksScreen(), null);

    expect(find.byKey(OverallWeeksKeys.chart), findsNothing);
  });

  group('layout', () {
    for (final locale in AppLocales.supported) {
      testWidgets('fits at large text in $locale', (tester) async {
        await pump(
          tester,
          const OverallWeeksScreen(),
          weeksOf([weak, empty, partial, full, full]),
          locale: locale,
          textScaler: const TextScaler.linear(1.6),
        );

        expect(find.byKey(OverallWeeksKeys.chart), findsOneWidget);
      });
    }
  });
}
