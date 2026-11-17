import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/goals/presentation/goal_sheets.dart';

import '../../../helpers/layout_harness.dart';
import '../goal_fixtures.dart';

Future<MetricFormat> _format(WidgetTester tester) async {
  late MetricFormat format;
  await pumpScaled(
    tester,
    screenHost(
      Builder(
        builder: (context) {
          format = MetricFormat.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
    textScaler: TextScaler.noScaling,
    brightness: Brightness.light,
    locale: const Locale('en'),
  );
  return format;
}

ReviewInputs _inputs({required List<int?> readiness}) => ReviewInputs(
  kind: f1.kind,
  week: f1.week,
  levers: f1.levers,
  adherencePrevious: f1.adherencePrevious,
  baseline: f1.baseline,
  effortRaisesInRow: f1.effortRaisesInRow,
  rate: f1.rate,
  targetPercent: f1.targetPercent,
  capPercent: f1.capPercent,
  previousPercentLow: f1.previousPercentLow,
  bmi: f1.bmi,
  pregnantOrBreastfeeding: f1.pregnantOrBreastfeeding,
  screeningPositive: f1.screeningPositive,
  bodyOn: f1.bodyOn,
  readiness: readiness,
  recoveryPrevious: f1.recoveryPrevious,
  energy: f1.energy,
  energyPrevious: f1.energyPrevious,
  foodOrWeight: f1.foodOrWeight,
  foodOrWeightPrevious: f1.foodOrWeightPrevious,
);

void main() {
  testWidgets('every lever sheet prints its constants', (tester) async {
    final format = await _format(tester);
    final l10n = format.l10n;
    expect(
      goalLeverCopy(format, LeverKind.steps).rule,
      l10n.goalsSheetStepsRule('5', '14', '1,000', '10,000'),
    );
    expect(
      goalLeverCopy(format, LeverKind.sleepWindow).rule,
      l10n.goalsSheetSleepRule('5', '15', '7', '9'),
    );
    expect(
      goalLeverCopy(format, LeverKind.strengthDays).rule,
      l10n.goalsSheetStrengthRule('20', '4'),
    );
    expect(
      goalLeverCopy(format, LeverKind.effortPoints).rule,
      l10n.goalsSheetPointsRule('4', '10', '15', '300', '80', '3'),
    );
    expect(
      goalLeverCopy(format, LeverKind.wakeTime).rule,
      l10n.goalsSheetWakeRule('30', '5'),
    );
    for (final kind in LeverKind.values) {
      final copy = goalLeverCopy(format, kind);
      for (final part in [copy.what, copy.source, copy.ours, copy.limits]) {
        expect(part, isNotEmpty);
      }
    }
  });

  testWidgets('the rule sheet names the rule, its condition and answer', (
    tester,
  ) async {
    final format = await _format(tester);
    final copy = goalRuleCopy(format, ReviewRule.recoveryWeek);
    expect(copy.title, 'Rule 4 of 11');
    expect(copy.rule, contains('Readiness under 55 on 4 of the last 7 days'));
    expect(copy.rule, contains('pause of 14 days'));
  });

  testWidgets('the rule inputs count low readiness and hide weight', (
    tester,
  ) async {
    final format = await _format(tester);
    final inputs = _inputs(readiness: [52, 49, 58, 54, null, 50, 66]);
    final shown = goalRuleYours(format, inputs, hidden: false);
    expect(shown, contains('Readiness under 55: 4.'));
    expect(shown, contains('Rate:'));
    final hidden = goalRuleYours(format, inputs, hidden: true);
    expect(hidden, isNot(contains('Rate:')));
    expect(hidden, isNot(contains('BMI')));
    expect(hidden, contains('Readiness under 55: 4.'));
  });
}
