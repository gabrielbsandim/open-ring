import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/features/open_score/presentation/overall_evidence_sheet.dart';
import 'package:open_ring/features/open_score/presentation/overall_screen.dart';

import 'overall_screen_test.dart' show full, historyOf, partial, pump, text;

Future<void> open(WidgetTester tester, OverallFactor factor) async {
  await tester.tap(find.byKey(OverallKeys.factor(factor)));
  await tester.pumpAndSettle();
}

String sheetText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(OverallEvidenceKeys.sheet),
        matching: find.byType(Text),
      ),
    )
    .map((widget) => widget.data ?? '')
    .join('\n');

void main() {
  for (final factor in OverallFactor.values) {
    testWidgets('the ${factor.name} row opens its sheet', (tester) async {
      await pump(tester, const OverallScreen(), historyOf(full));
      await open(tester, factor);

      expect(find.byKey(OverallEvidenceKeys.sheet), findsOneWidget);
      expect(find.byKey(OverallEvidenceKeys.rule), findsOneWidget);
      expect(find.byKey(OverallEvidenceKeys.association), findsOneWidget);
      expect(sheetText(tester), contains('What is our choice'));
    });
  }

  testWidgets('the rule numbers come from the constants', (tester) async {
    await pump(tester, const OverallScreen(), historyOf(full));
    await open(tester, OverallFactor.restingHeartRate);

    expect(
      sheetText(tester),
      contains(
        '${overallRestingZeroAt.round()} or more is worth zero, '
        '${overallRestingFullAt.round()} or less is worth everything',
      ),
    );
    expect(sheetText(tester), contains('The $overallWindowDays days before'));
    expect(sheetText(tester), contains('needs $overallMinDays valid days'));
  });

  testWidgets('a factor outside the count says so and has no points', (
    tester,
  ) async {
    await pump(tester, const OverallScreen(), historyOf(partial));
    await open(tester, OverallFactor.fitness);

    expect(find.byKey(OverallEvidenceKeys.points), findsNothing);
    expect(sheetText(tester), contains('Its 30 points leave the count'));
    expect(find.byKey(OverallEvidenceKeys.window), findsNothing);
  });

  testWidgets('the movement sheet shows its three parts', (tester) async {
    await pump(tester, const OverallScreen(), historyOf(full));
    await open(tester, OverallFactor.movement);

    final parts = full.movementPoints!;
    expect(find.byKey(OverallEvidenceKeys.parts), findsOneWidget);
    expect(sheetText(tester), contains('Moderate minutes'));
    expect(sheetText(tester), contains('Strength days'));
    expect(sheetText(tester), contains('of 4'));
    expect(parts.strength, closeTo(3, 1e-9));
    expect(text(tester, OverallEvidenceKeys.points), contains('of 20'));
  });

  testWidgets('an older adult reads the lower step mark', (tester) async {
    const older = OverallInputs(
      restingHeartRate: 53,
      sleepHours: 6.6,
      sleepRegularity: 66,
      weeklyMinutes: 132,
      dailySteps: 6900,
      olderAdult: true,
    );
    await pump(tester, const OverallScreen(), historyOf(older));
    await open(tester, OverallFactor.movement);

    expect(sheetText(tester), contains('7,000 is worth everything'));
  });

  testWidgets('the Body sheet shows no number while numbers are hidden', (
    tester,
  ) async {
    await pump(tester, const OverallScreen(), historyOf(full), hidden: true);
    await open(tester, OverallFactor.body);

    expect(find.byKey(OverallEvidenceKeys.points), findsNothing);
    expect(sheetText(tester), isNot(contains('0.49')));
    expect(
      sheetText(tester),
      contains('From your last measurement in the Body module.'),
    );
  });

  testWidgets('the Body sheet shows the ratio and points otherwise', (
    tester,
  ) async {
    await pump(tester, const OverallScreen(), historyOf(full));
    await open(tester, OverallFactor.body);

    expect(sheetText(tester), contains('0.49'));
    expect(find.byKey(OverallEvidenceKeys.points), findsOneWidget);
  });

  testWidgets('a Body row scored on weight and height explains that rule', (
    tester,
  ) async {
    const bmiOnly = OverallInputs(
      restingHeartRate: 53,
      sleepHours: 6.6,
      sleepRegularity: 66,
      weeklyMinutes: 132,
      dailySteps: 6900,
      bmi: 27,
    );
    await pump(tester, const OverallScreen(), historyOf(bmiOnly));
    await open(tester, OverallFactor.body);

    expect(sheetText(tester), contains('The body mass index: weight divided'));
    expect(
      sheetText(tester),
      contains(
        '${bmiFullAt.round()} or less is worth everything, '
        '${bmiZeroAt.round()} or more is worth zero',
      ),
    );
    expect(sheetText(tester), contains('Below $bmiFloor the row leaves'));
    expect(sheetText(tester), isNot(contains('0.50 or less')));
    expect(text(tester, OverallEvidenceKeys.points), contains('of 5'));
  });

  testWidgets('sleep regularity asks for pairs of days, not days', (
    tester,
  ) async {
    await pump(tester, const OverallScreen(), historyOf(full));
    await open(tester, OverallFactor.sleepRegularity);

    expect(
      sheetText(tester),
      contains('needs $sleepRegularityMinPairs pairs of days in a row'),
    );
    expect(sheetText(tester), isNot(contains('valid days')));
  });

  group('layout', () {
    for (final locale in AppLocales.supported) {
      testWidgets('every sheet fits at large text in $locale', (tester) async {
        await pump(
          tester,
          const OverallScreen(),
          historyOf(full),
          locale: locale,
          textScaler: const TextScaler.linear(1.6),
        );
        for (final factor in OverallFactor.values) {
          await open(tester, factor);
          final sheet = find.byKey(OverallEvidenceKeys.sheet);
          expect(sheet, findsOneWidget);
          Navigator.of(tester.element(sheet)).pop();
          await tester.pumpAndSettle();
        }
      });
    }
  });
}
