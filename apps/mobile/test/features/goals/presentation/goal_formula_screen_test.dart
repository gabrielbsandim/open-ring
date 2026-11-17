import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/presentation/goal_formula_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../goal_fixtures.dart';

GoalReviewView _view(ReviewRule rule) => GoalReviewView(
  week: GoalWeek(
    goalId: 1,
    monday: goalDay(12, 7),
    inputs: f1,
    rule: rule,
    action: ReviewAction.hold,
    change: null,
    answer: null,
  ),
  review: reviewWeek(f1),
);

List<Override> _overrides({required bool on, ReviewRule? rule}) => [
  goalsEnabledProvider.overrideWithValue(on),
  goalReviewProvider.overrideWith(
    (ref) async => rule == null ? null : _view(rule),
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  bool on = true,
  ReviewRule? rule,
  Locale locale = const Locale('en'),
  double scale = 1,
  Size size = const Size(400, 6000),
  Brightness brightness = Brightness.light,
}) => pumpScaled(
  tester,
  screenHost(const GoalFormulaScreen()),
  textScaler: TextScaler.linear(scale),
  brightness: brightness,
  locale: locale,
  size: size,
  overrides: _overrides(on: on, rule: rule),
);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(GoalFormulaScreen)));

List<String> _texts(WidgetTester tester, Key within) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(of: find.byKey(within), matching: find.byType(Text)),
  ))
    text.data ?? text.textSpan?.toPlainText() ?? '',
];

void main() {
  testWidgets('the rate prints the window, minimum and band', (tester) async {
    await _pump(tester);
    expect(
      _texts(tester, GoalFormulaKeys.rate),
      contains(
        _l10n(tester).goalsFormulaRateBody('28', '8', '14', '0.5', '1.5'),
      ),
    );
  });

  testWidgets('the target prints the paces, caps and block', (tester) async {
    await _pump(tester);
    expect(
      _texts(tester, GoalFormulaKeys.target),
      contains(
        _l10n(tester).goalsFormulaTargetBody(
          '0.5',
          '0.25',
          '25',
          '0.5',
          '30',
          '0.75',
          '1',
          '12',
          '10',
          '4',
        ),
      ),
    );
  });

  testWidgets('the levers print their steps and limits', (tester) async {
    await _pump(tester);
    final l10n = _l10n(tester);
    expect(
      _texts(tester, GoalFormulaKeys.levers),
      containsAll([
        l10n.goalsFormulaLeversBody('3', '5'),
        l10n.goalsFormulaLeverSteps('14', '1,000', '10,000'),
        l10n.goalsFormulaLeverEffort('4', '10', '15', '300'),
        l10n.goalsFormulaLeverStrength('2', '4'),
        l10n.goalsFormulaLeverSleep('15', '7', '9'),
        l10n.goalsFormulaLeverWake('30'),
        l10n.goalsFormulaLeversFood,
      ]),
    );
  });

  testWidgets('the eleven rules are listed in the order of the code', (
    tester,
  ) async {
    await _pump(tester);
    final tops = [
      for (final rule in ReviewRule.values)
        tester.getTopLeft(find.byKey(GoalFormulaKeys.rule(rule))).dy,
    ];
    expect(tops, [...tops]..sort());
    expect(tops.toSet(), hasLength(ReviewRule.values.length));
    expect(
      _texts(tester, GoalFormulaKeys.rule(ReviewRule.recoveryWeek)),
      contains(_l10n(tester).goalsFormulaRuleRecovery('55', '4')),
    );
    expect(
      _texts(tester, GoalFormulaKeys.rule(ReviewRule.recoveryWeek)),
      contains(
        '${_l10n(tester).goalsFormulaAnswerRecovery('14')} · '
        '${_l10n(tester).goalsFormulaScopeAll}',
      ),
    );
    expect(
      _texts(tester, GoalFormulaKeys.rule(ReviewRule.pauseFastLoss)),
      contains(
        '${_l10n(tester).goalsFormulaAnswerPauseDays('28')} · '
        '${_l10n(tester).goalsFormulaScopeLoseFat}',
      ),
    );
  });

  testWidgets('the rule of the last review is marked', (tester) async {
    await _pump(tester, rule: ReviewRule.shrink);
    expect(_texts(tester, GoalFormulaKeys.current), [
      _l10n(tester).goalsFormulaReviewCurrent('8'),
    ]);
    final marked = tester.getSemantics(
      find.byKey(GoalFormulaKeys.rule(ReviewRule.shrink)),
    );
    expect(marked.flagsCollection.isSelected, Tristate.isTrue);
  });

  testWidgets('no review, or Goals off, marks no rule', (tester) async {
    await _pump(tester);
    expect(find.byKey(GoalFormulaKeys.current), findsNothing);
    await _pump(tester, on: false, rule: ReviewRule.shrink);
    expect(find.byKey(GoalFormulaKeys.current), findsNothing);
  });

  testWidgets('the protections print their constants', (tester) async {
    await _pump(tester);
    final l10n = _l10n(tester);
    expect(
      _texts(tester, GoalFormulaKeys.protections),
      containsAll([
        l10n.goalsFormulaProtect1('2'),
        l10n.goalsFormulaProtect2('18'),
        l10n.goalsFormulaProtect3('18.5'),
        l10n.goalsFormulaProtect4('4'),
        l10n.goalsFormulaProtect5('55', '4'),
      ]),
    );
  });

  for (final brightness in Brightness.values) {
    for (final locale in const [Locale('en'), Locale('de')]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('lays out in $locale at ${scale}x, ${brightness.name}', (
          tester,
        ) async {
          await _pump(
            tester,
            rule: ReviewRule.build,
            locale: locale,
            scale: scale,
            size: phoneSize,
            brightness: brightness,
          );
          await tester.scrollUntilVisible(
            find.byKey(GoalFormulaKeys.cannot),
            300,
            scrollable: find.byType(Scrollable).first,
            maxScrolls: 300,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
