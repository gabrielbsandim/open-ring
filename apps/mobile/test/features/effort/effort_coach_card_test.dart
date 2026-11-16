import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/presentation/effort_coach_card.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../helpers/layout_harness.dart';

CoachAdvice _advice(
  CoachRule rule, {
  double? acute = 60,
  double? chronic = 50,
  double? chronicWeekAgo = 48,
  double? yesterdayLoad = 23,
  int? hardFrom = 120,
  int hardDays = 0,
  int daysSinceEasy = 1,
}) => CoachAdvice(
  rule: rule,
  acute: acute,
  chronic: chronic,
  chronicWeekAgo: chronicWeekAgo,
  yesterdayLoad: yesterdayLoad,
  hardFrom: hardFrom,
  hardDays: hardDays,
  daysSinceEasy: daysSinceEasy,
);

final Map<String, EffortCoachCard> _cards = {
  'sick': (advice: _advice(CoachRule.sick), readiness: 80, covered: false),
  'low readiness': (
    advice: _advice(CoachRule.lowReadiness),
    readiness: 52,
    covered: false,
  ),
  'hard run': (
    advice: _advice(CoachRule.hardRun, hardDays: 2, yesterdayLoad: 140),
    readiness: 74,
    covered: false,
  ),
  'no easy day': (
    advice: _advice(CoachRule.noEasyDay, daysSinceEasy: 6, chronic: 61),
    readiness: 74,
    covered: false,
  ),
  'fair readiness': (
    advice: _advice(CoachRule.fairReadiness),
    readiness: 63,
    covered: false,
  ),
  'spike': (
    advice: _advice(CoachRule.spike, acute: 96, chronicWeekAgo: 41),
    readiness: 74,
    covered: false,
  ),
  'hard yesterday': (
    advice: _advice(CoachRule.hardYesterday, yesterdayLoad: 133),
    readiness: 74,
    covered: false,
  ),
  'good readiness': (
    advice: _advice(CoachRule.goodReadiness),
    readiness: 78,
    covered: false,
  ),
  'covered': (
    advice: _advice(CoachRule.goodReadiness),
    readiness: 78,
    covered: true,
  ),
  'waiting for load': (
    advice: _advice(
      CoachRule.goodReadiness,
      acute: null,
      chronic: null,
      chronicWeekAgo: null,
      hardFrom: null,
    ),
    readiness: 78,
    covered: false,
  ),
  'no readiness': (
    advice: _advice(CoachRule.noReadiness),
    readiness: null,
    covered: false,
  ),
};

List<Override> _overrides({
  Set<ModuleId> modules = const {ModuleId.effort},
  EffortCoachCard? card,
  Object? error,
}) => [
  moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
  effortCoachCardProvider.overrideWith((ref) async {
    if (error != null) throw StateError('$error');
    return card ?? _cards['good readiness']!;
  }),
];

Future<void> _pump(
  WidgetTester tester, {
  Set<ModuleId> modules = const {ModuleId.effort},
  EffortCoachCard? card,
  Object? error,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Brightness brightness = Brightness.dark,
}) => pumpScaled(
  tester,
  screenHost(
    const Scaffold(body: SingleChildScrollView(child: EffortCoachSlot())),
  ),
  textScaler: textScaler,
  brightness: brightness,
  locale: locale,
  overrides: _overrides(modules: modules, card: card, error: error),
);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));

String _text(WidgetTester tester, Key key) =>
    switch (tester.widget(find.byKey(key))) {
      final Text text => text.data ?? text.textSpan!.toPlainText(),
      final CaptionText text => text.text,
      final other => throw StateError('no text in ${other.runtimeType}'),
    };

void main() {
  group('the gate', () {
    testWidgets('with Effort off there is no card', (tester) async {
      await _pump(tester, modules: const {ModuleId.openScore});
      expect(find.byKey(EffortCoachKeys.card), findsNothing);
    });

    testWidgets('with Effort on the card shows', (tester) async {
      await _pump(tester);
      expect(find.byKey(EffortCoachKeys.card), findsOneWidget);
    });

    testWidgets('when the advice fails there is no card', (tester) async {
      await _pump(tester, error: 'no data');
      expect(find.byKey(EffortCoachKeys.card), findsNothing);
    });
  });

  group('the card of each rule', () {
    testWidgets('good readiness says Push with rule 8 and its numbers', (
      tester,
    ) async {
      await _pump(tester);
      final l10n = _l10n(tester);
      expect(_text(tester, EffortCoachKeys.verdict), l10n.effortCoachPush);
      expect(
        _text(tester, EffortCoachKeys.line),
        l10n.effortCoachLineGoodReadiness,
      );
      expect(
        _text(tester, EffortCoachKeys.rule),
        '${l10n.effortCoachRuleFired('8')} '
        '${l10n.effortCoachWhyGoodNotHard('78', '70', '23', '120')}',
      );
      expect(_text(tester, EffortCoachKeys.note), l10n.effortCoachNotePush);
    });

    testWidgets('a covered week changes the line and not the rule', (
      tester,
    ) async {
      await _pump(tester, card: _cards['covered']);
      final l10n = _l10n(tester);
      expect(_text(tester, EffortCoachKeys.line), l10n.effortCoachLineCovered);
      expect(
        _text(tester, EffortCoachKeys.rule),
        startsWith(l10n.effortCoachRuleFired('8')),
      );
    });

    testWidgets('without load lines rule 8 says the load rules wait', (
      tester,
    ) async {
      await _pump(tester, card: _cards['waiting for load']);
      final l10n = _l10n(tester);
      expect(
        _text(tester, EffortCoachKeys.rule),
        '${l10n.effortCoachRuleFired('8')} '
        '${l10n.effortCoachWhyGoodWaiting('78', '70', '14')}',
      );
    });

    testWidgets('low readiness says Recover with rule 2', (tester) async {
      await _pump(tester, card: _cards['low readiness']);
      final l10n = _l10n(tester);
      expect(_text(tester, EffortCoachKeys.verdict), l10n.effortCoachRecover);
      expect(
        _text(tester, EffortCoachKeys.rule),
        '${l10n.effortCoachRuleFired('2')} '
        '${l10n.effortCoachWhyLowReadiness('52', '55')}',
      );
      expect(_text(tester, EffortCoachKeys.note), l10n.effortCoachNoteRecover);
    });

    testWidgets('a hard yesterday says Maintain with both numbers', (
      tester,
    ) async {
      await _pump(tester, card: _cards['hard yesterday']);
      final l10n = _l10n(tester);
      expect(_text(tester, EffortCoachKeys.verdict), l10n.effortCoachMaintain);
      expect(
        _text(tester, EffortCoachKeys.rule),
        '${l10n.effortCoachRuleFired('7')} '
        '${l10n.effortCoachWhyHardYesterday('133', '120')}',
      );
      expect(_text(tester, EffortCoachKeys.note), l10n.effortCoachNoteMaintain);
    });

    testWidgets('no easy day prints half the 28 day line, rounded', (
      tester,
    ) async {
      await _pump(tester, card: _cards['no easy day']);
      final l10n = _l10n(tester);
      expect(
        _text(tester, EffortCoachKeys.rule),
        '${l10n.effortCoachRuleFired('4')} '
        '${l10n.effortCoachWhyNoEasyDay('31', '6')}',
      );
    });

    final others = <String, String Function(AppLocalizations)>{
      'sick': (l10n) =>
          '${l10n.effortCoachRuleFired('1')} ${l10n.effortCoachWhySick}',
      'hard run': (l10n) =>
          '${l10n.effortCoachRuleFired('3')} '
          '${l10n.effortCoachWhyHardRun('2', '120')}',
      'fair readiness': (l10n) =>
          '${l10n.effortCoachRuleFired('5')} '
          '${l10n.effortCoachWhyFairReadiness('63', '55', '69')}',
      'spike': (l10n) =>
          '${l10n.effortCoachRuleFired('6')} '
          '${l10n.effortCoachWhySpike('96', '41')}',
      'no readiness': (l10n) =>
          '${l10n.effortCoachRuleFired('9')} ${l10n.effortCoachWhyNoReadiness}',
    };
    for (final MapEntry(key: name, value: expected) in others.entries) {
      testWidgets('$name prints its own rule and numbers', (tester) async {
        await _pump(tester, card: _cards[name]);
        expect(_text(tester, EffortCoachKeys.rule), expected(_l10n(tester)));
      });
    }

    testWidgets('no readiness has its own line', (tester) async {
      await _pump(tester, card: _cards['no readiness']);
      expect(
        _text(tester, EffortCoachKeys.line),
        _l10n(tester).effortCoachLineNoReadiness,
      );
    });
  });

  group('layout', () {
    for (final locale in AppLocales.supported) {
      for (final MapEntry(key: name, value: card) in _cards.entries) {
        testWidgets('fits 2x in $locale with $name', (tester) async {
          await _pump(
            tester,
            card: card,
            locale: locale,
            textScaler: const TextScaler.linear(2),
            brightness: Brightness.light,
          );
          expect(find.byKey(EffortCoachKeys.card), findsOneWidget);
        });
      }
    }
  });
}
