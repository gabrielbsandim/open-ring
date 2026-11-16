import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/energy/presentation/energy_evidence_sheet.dart';
import 'package:open_ring/features/energy/presentation/energy_formula_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

Future<void> _pump(
  WidgetTester tester, {
  EnergyGate gate = EnergyGate.on,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Brightness brightness = Brightness.dark,
}) => pumpScaled(
  tester,
  screenHost(const EnergyFormulaScreen()),
  textScaler: textScaler,
  brightness: brightness,
  locale: locale,
  overrides: [energyGateProvider.overrideWithValue(gate)],
);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(EnergyFormulaScreen)));

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 300,
  );
  await tester.pumpAndSettle();
}

Iterable<String> _texts(WidgetTester tester, Finder within) sync* {
  final bodies = find.descendant(of: within, matching: find.byType(BodyText));
  for (final body in tester.widgetList<BodyText>(bodies)) {
    yield body.text;
  }
}

void main() {
  group('the rules', () {
    testWidgets('the resting burn prints the constants of the equation', (
      tester,
    ) async {
      await _pump(tester);
      final card = find.byKey(EnergyFormulaKeys.rule(EnergyEvidence.resting));
      await _reveal(tester, card);

      expect(
        _texts(tester, card),
        contains(
          _l10n(
            tester,
          ).energyRuleResting('9.99', '6.25', '4.92', '5', '161', '10', '50'),
        ),
      );
    });

    testWidgets('the Base, the steps and the workouts print their rule', (
      tester,
    ) async {
      await _pump(tester);
      final l10n = _l10n(tester);
      final rules = {
        EnergyEvidence.base: l10n.energyRuleBase('1.3'),
        EnergyEvidence.steps: l10n.energyRuleSteps('0.415', '0.5'),
        EnergyEvidence.workouts: l10n.energyRuleWorkouts,
      };

      for (final MapEntry(key: kind, value: rule) in rules.entries) {
        final card = find.byKey(EnergyFormulaKeys.rule(kind));
        await _reveal(tester, card);
        expect(_texts(tester, card), contains(rule));
      }
    });

    testWidgets('no rule shows a value of the person', (tester) async {
      await _pump(tester);

      expect(find.byKey(EnergyEvidenceKeys.yours), findsNothing);
    });
  });

  testWidgets('the margins come from the constants', (tester) async {
    await _pump(tester);
    final card = find.byKey(EnergyFormulaKeys.margins);
    await _reveal(tester, card);

    expect(
      _texts(tester, card),
      contains(_l10n(tester).energyFormulaMargin1('10', '15', '50')),
    );
  });

  testWidgets('the sources are listed', (tester) async {
    await _pump(tester);
    final card = find.byKey(EnergyFormulaKeys.sources);
    await _reveal(tester, card);

    for (final source in energyFormulaSources) {
      expect(
        find.descendant(of: card, matching: find.text(source)),
        findsOneWidget,
      );
    }
  });

  for (final gate in [EnergyGate.off, EnergyGate.underage, EnergyGate.hidden]) {
    testWidgets('shows its rule cards while the gate is ${gate.name}', (
      tester,
    ) async {
      await _pump(tester, gate: gate);

      expect(find.byType(BodyText), findsWidgets);
      for (final kind in EnergyEvidence.values) {
        final card = find.byKey(EnergyFormulaKeys.rule(kind));
        await _reveal(tester, card);
        expect(card, findsOneWidget);
        expect(_texts(tester, card), isNotEmpty);
      }
      await _reveal(tester, find.byKey(EnergyFormulaKeys.margins));
      expect(find.byKey(EnergyFormulaKeys.margins), findsOneWidget);
      await _reveal(tester, find.byKey(EnergyFormulaKeys.sources));
      expect(find.byKey(EnergyFormulaKeys.sources), findsOneWidget);
    });

    testWidgets('prints the same intro while the gate is ${gate.name}', (
      tester,
    ) async {
      await _pump(tester, gate: gate);

      expect(find.text(_l10n(tester).energyFormulaIntro), findsOneWidget);
    });
  }

  group('layout', () {
    for (final layout in layoutMatrix()) {
      testWidgets('fits $layout', (tester) async {
        await _pump(
          tester,
          locale: layout.locale,
          textScaler: layout.textScaler,
          brightness: layout.brightness,
        );
        await _reveal(tester, find.byKey(EnergyFormulaKeys.sources));

        expect(find.byKey(EnergyFormulaKeys.sources), findsOneWidget);
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

        for (final kind in EnergyEvidence.values) {
          final card = find.byKey(EnergyFormulaKeys.rule(kind));
          await _reveal(tester, card);
          for (final text in _texts(tester, card)) {
            expect(text, isNot(contains('{')));
          }
        }
        await _reveal(tester, find.byKey(EnergyFormulaKeys.margins));
        for (final text in _texts(
          tester,
          find.byKey(EnergyFormulaKeys.margins),
        )) {
          expect(text, isNot(contains('{')));
        }
      });
    }
  });
}
