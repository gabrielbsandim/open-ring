import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/presentation/effort_formula_screen.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../helpers/ble_fakes.dart';
import '../../helpers/layout_harness.dart';
import '../../helpers/ring_fakes.dart';

EffortCoachCard _coach(CoachRule rule) => (
  advice: CoachAdvice(
    rule: rule,
    acute: 60,
    chronic: 50,
    chronicWeekAgo: 48,
    yesterdayLoad: 23,
    hardFrom: 120,
    hardDays: 0,
    daysSinceEasy: 1,
  ),
  readiness: 78,
  covered: false,
);

List<Override> _overrides(Set<ModuleId> modules, CoachRule rule) => [
  ...bleOverrides(),
  ...ringOverrides(),
  moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
  effortCoachCardProvider.overrideWith((ref) async => _coach(rule)),
];

Future<void> _pump(
  WidgetTester tester, {
  Set<ModuleId> modules = const {ModuleId.effort},
  CoachRule rule = CoachRule.hardYesterday,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Brightness brightness = Brightness.dark,
}) => pumpScaled(
  tester,
  screenHost(const EffortFormulaScreen()),
  textScaler: textScaler,
  brightness: brightness,
  locale: locale,
  overrides: _overrides(modules, rule),
);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(EffortFormulaScreen)));

Future<void> _reveal(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 300,
  );
  await tester.pumpAndSettle();
}

Iterable<String> _texts(WidgetTester tester, Key within) sync* {
  final card = find.byKey(within);
  final found = find.descendant(of: card, matching: find.byType(Text));
  for (final text in tester.widgetList<Text>(found)) {
    yield text.data ?? '';
  }
}

void main() {
  group('the parts print their constants', () {
    testWidgets('Effort Points', (tester) async {
      await _pump(tester);
      await _reveal(tester, EffortFormulaKeys.points);

      expect(
        _texts(tester, EffortFormulaKeys.points),
        contains(
          _l10n(tester)
              .effortFormulaPointsBody('2', '64', '77', '3', '6', '100'),
        ),
      );
    });

    testWidgets('the week', (tester) async {
      await _pump(tester);
      await _reveal(tester, EffortFormulaKeys.week);

      expect(
        _texts(tester, EffortFormulaKeys.week),
        contains(_l10n(tester).effortFormulaWeekBody('150', '2', '20')),
      );
    });

    testWidgets('session load, with one default for every workout type', (
      tester,
    ) async {
      await _pump(tester);
      await _reveal(tester, EffortFormulaKeys.defaults);

      expect(
        _texts(tester, EffortFormulaKeys.load),
        contains(
          _l10n(tester).effortFormulaLoadBody('50, 60, 70, 80, 90', '2'),
        ),
      );
      final defaults = tester
          .widget<CaptionText>(find.byKey(EffortFormulaKeys.defaults))
          .text;
      expect(defaults, contains('Running 3'));
      expect(defaults, contains('2.5'));
      expect(defaults, contains('Yoga 1'));
    });

    testWidgets('daily load and the two lines', (tester) async {
      await _pump(tester);
      await _reveal(tester, EffortFormulaKeys.lines);

      expect(
        _texts(tester, EffortFormulaKeys.lines),
        contains(
          _l10n(tester).effortFormulaLinesBody(
            '1.5',
            '7',
            '0.25',
            '28',
            '0.069',
            '7',
            '14',
          ),
        ),
      );
    });
  });

  group('the coach rules', () {
    testWidgets('lists the nine rules in order with their constants', (
      tester,
    ) async {
      await _pump(tester);
      final l10n = _l10n(tester);
      final conditions = {
        CoachRule.sick: l10n.effortFormulaRuleSick,
        CoachRule.lowReadiness: l10n.effortFormulaRuleReadinessUnder('55'),
        CoachRule.hardRun: l10n.effortFormulaRuleHardRun('2'),
        CoachRule.noEasyDay: l10n.effortFormulaRuleNoEasy('6'),
        CoachRule.fairReadiness: l10n.effortFormulaRuleReadinessUnder('70'),
        CoachRule.spike: l10n.effortFormulaRuleSpike('7', '1.5', '28', '150'),
        CoachRule.hardYesterday: l10n.effortFormulaRuleHardYesterday,
        CoachRule.goodReadiness: l10n.effortFormulaRuleReadinessFrom('70'),
        CoachRule.noReadiness: l10n.effortFormulaRuleNoReadiness,
      };

      expect(conditions.keys, CoachRule.values);
      for (final MapEntry(key: rule, value: condition) in conditions.entries) {
        final key = EffortFormulaKeys.rule(rule);
        await _reveal(tester, key);
        expect(_texts(tester, key).toList(), [
          '${rule.number}',
          condition,
          isNotEmpty,
        ]);
      }
    });

    testWidgets('the notes carry the day counts and the rule numbers', (
      tester,
    ) async {
      await _pump(tester);
      await _reveal(tester, EffortFormulaKeys.history);
      final l10n = _l10n(tester);

      expect(
        _texts(tester, EffortFormulaKeys.coach),
        containsAll([
          l10n.effortFormulaCoachNote('120', '1.5', '28', '50', '1'),
          l10n.effortFormulaCoachHistory(
            '4',
            '14',
            '7',
            '15',
            '3',
            '16',
            '6',
            '21',
          ),
        ]),
      );
    });

    test('the day counts of the history note are where the rules start', () {
      CoachAdvice advice(List<double> dailyLoad) =>
          coachAdvice(readiness: null, sick: false, dailyLoad: dailyLoad);
      List<double> flat(int days) => List.filled(days, 10);

      expect(advice(flat(13)).chronic, isNull);
      expect(advice(flat(14)).chronic, isNotNull);
      expect(advice([...flat(13), 500]).hardDays, 0);
      expect(advice([...flat(14), 500]).rule, CoachRule.hardYesterday);
      expect(advice([...flat(13), 500, 5000]).hardDays, 1);
      expect(advice([...flat(14), 500, 5000]).rule, CoachRule.hardRun);
      expect(advice(flat(20)).chronicWeekAgo, isNull);
      expect(advice(flat(21)).chronicWeekAgo, isNotNull);
    });

    testWidgets('marks the rule on the card while Effort is on', (
      tester,
    ) async {
      await _pump(tester);
      await _reveal(tester, EffortFormulaKeys.current);

      expect(
        tester.widget<BodyText>(find.byKey(EffortFormulaKeys.current)).text,
        _l10n(tester).effortFormulaCoachCurrent('7'),
      );
    });

    testWidgets('marks no rule while Effort is off', (tester) async {
      await _pump(tester, modules: const {ModuleId.openScore});
      await _reveal(tester, EffortFormulaKeys.rule(CoachRule.noReadiness));

      expect(find.byKey(EffortFormulaKeys.current), findsNothing);
      expect(find.byKey(EffortFormulaKeys.coach), findsOneWidget);
    });
  });

  testWidgets('the four lists print their constants', (tester) async {
    await _pump(tester);
    final l10n = _l10n(tester);
    final lists = {
      EffortFormulaKeys.sources: [
        l10n.effortFormulaSource1('2', '150'),
        l10n.effortFormulaSource2('64', '77'),
        l10n.effortFormulaSource3('100'),
        l10n.effortFormulaSource4,
      ],
      EffortFormulaKeys.ours: [
        l10n.effortFormulaOurs1,
        l10n.effortFormulaOurs2('20'),
        l10n.effortFormulaOurs3('1.5'),
        l10n.effortFormulaOurs4('14'),
        l10n.effortFormulaOurs5,
      ],
      EffortFormulaKeys.unchecked: [
        l10n.effortFormulaUnchecked1('2'),
        l10n.effortFormulaUnchecked2,
        l10n.effortFormulaUnchecked3,
        l10n.effortFormulaUnchecked4,
        l10n.effortFormulaUnchecked5,
      ],
      EffortFormulaKeys.cannot: [
        l10n.effortFormulaCannot1,
        l10n.effortFormulaCannot2,
        l10n.effortFormulaCannot3,
        l10n.effortFormulaCannot4,
      ],
    };

    for (final MapEntry(:key, value: facts) in lists.entries) {
      await _reveal(tester, key);
      expect(_texts(tester, key).skip(1), facts);
    }
  });

  group('layout', () {
    for (final layout in layoutMatrix()) {
      testWidgets('fits $layout', (tester) async {
        await _pump(
          tester,
          locale: layout.locale,
          textScaler: layout.textScaler,
          brightness: layout.brightness,
        );
        await _reveal(tester, EffortFormulaKeys.cannot);

        expect(find.byKey(EffortFormulaKeys.cannot), findsOneWidget);
      });
    }

    for (final locale in AppLocales.supported) {
      testWidgets('fits 2.0x in $locale with no placeholder open', (
        tester,
      ) async {
        await _pump(
          tester,
          locale: locale,
          textScaler: const TextScaler.linear(2),
        );

        for (final key in [
          EffortFormulaKeys.points,
          EffortFormulaKeys.week,
          EffortFormulaKeys.load,
          EffortFormulaKeys.lines,
          EffortFormulaKeys.coach,
          EffortFormulaKeys.sources,
          EffortFormulaKeys.ours,
          EffortFormulaKeys.unchecked,
          EffortFormulaKeys.cannot,
        ]) {
          await _reveal(tester, key);
          for (final text in _texts(tester, key)) {
            expect(text, isNot(contains('{')));
          }
        }
      });
    }
  });
}
