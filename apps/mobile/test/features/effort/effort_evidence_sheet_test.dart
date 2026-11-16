import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/effort/presentation/effort_evidence_sheet.dart';
import 'package:open_ring/features/energy/presentation/energy_evidence_sheet.dart';

import '../../helpers/layout_harness.dart';

Future<void> _pump(
  WidgetTester tester,
  EffortEvidence kind, {
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
}) => pumpScaled(
  tester,
  screenHost(EffortEvidenceSheet(kind: kind, yours: 'mine')),
  textScaler: textScaler,
  brightness: Brightness.dark,
  locale: locale,
);

EffortEvidenceCopy _copy(WidgetTester tester, EffortEvidence kind) =>
    effortEvidenceCopy(
      MetricFormat.of(tester.element(find.byType(EffortEvidenceSheet))),
      kind,
    );

void main() {
  group('the copy carries the constants', () {
    testWidgets('points', (tester) async {
      await _pump(tester, EffortEvidence.points);
      final copy = _copy(tester, EffortEvidence.points);
      final l10n = MetricFormat.of(
        tester.element(find.byType(EffortEvidenceSheet)),
      ).l10n;

      expect(copy.title, l10n.effortFormulaPointsTitle);
      expect(copy.what, l10n.effortSheetPointsWhat('2'));
      expect(copy.source, l10n.effortSheetPointsSource('150'));
      expect(copy.limits, l10n.effortSheetPointsLimits('150'));
    });

    testWidgets('strength days', (tester) async {
      await _pump(tester, EffortEvidence.strength);
      final copy = _copy(tester, EffortEvidence.strength);
      final l10n = MetricFormat.of(
        tester.element(find.byType(EffortEvidenceSheet)),
      ).l10n;

      expect(copy.rule, l10n.effortSheetStrengthRule('20'));
      expect(copy.source, l10n.effortSheetStrengthSource('2'));
      expect(copy.ours, l10n.effortSheetStrengthOurs('20'));
    });

    testWidgets('the load lines', (tester) async {
      await _pump(tester, EffortEvidence.lines);
      final copy = _copy(tester, EffortEvidence.lines);
      final l10n = MetricFormat.of(
        tester.element(find.byType(EffortEvidenceSheet)),
      ).l10n;

      expect(copy.what, l10n.effortSheetLinesWhat('7', '28'));
      expect(
        copy.rule,
        l10n.effortSheetLinesRule('0.25', '7', '0.069', '28', '7'),
      );
      expect(copy.limits, l10n.effortLoadNote);
    });

    testWidgets('brisk walking', (tester) async {
      await _pump(tester, EffortEvidence.walk);
      final copy = _copy(tester, EffortEvidence.walk);
      final l10n = MetricFormat.of(
        tester.element(find.byType(EffortEvidenceSheet)),
      ).l10n;

      expect(copy.title, l10n.effortBriskWalking);
      expect(copy.rule, l10n.effortSheetWalkRule('100', '1.5'));
      expect(copy.source, l10n.effortSheetWalkSource('100'));
      expect(copy.ours, l10n.effortSheetWalkOurs('1.5'));
    });

    testWidgets('one session', (tester) async {
      await _pump(tester, EffortEvidence.session);
      final copy = _copy(tester, EffortEvidence.session);
      final l10n = MetricFormat.of(
        tester.element(find.byType(EffortEvidenceSheet)),
      ).l10n;

      expect(copy.title, l10n.effortFormulaLoadTitle);
      expect(copy.rule, l10n.effortSheetSessionRule);
      expect(copy.limits, l10n.effortFormulaCannot1);
    });

    testWidgets('the coach card', (tester) async {
      await _pump(tester, EffortEvidence.coach);
      final copy = _copy(tester, EffortEvidence.coach);
      final l10n = MetricFormat.of(
        tester.element(find.byType(EffortEvidenceSheet)),
      ).l10n;

      expect(copy.title, l10n.effortFormulaCoachTitle);
      expect(copy.rule, l10n.effortSheetCoachRule('9'));
      expect(copy.ours, l10n.effortFormulaOurs5);
      expect(copy.limits, l10n.effortFormulaCannot4);
    });
  });

  testWidgets('a sheet shows the six sections and the reader numbers', (
    tester,
  ) async {
    await _pump(tester, EffortEvidence.walk);
    final copy = _copy(tester, EffortEvidence.walk);

    expect(
      [
        for (final section in tester.widgetList<EnergyEvidenceSection>(
          find.byType(EnergyEvidenceSection),
        ))
          section.body,
      ],
      [copy.what, 'mine', copy.rule, copy.source, copy.ours, copy.limits],
    );
    expect(find.byKey(EffortEvidenceKeys.formula), findsOneWidget);
  });

  group('layout', () {
    for (final locale in AppLocales.supported) {
      for (final kind in EffortEvidence.values) {
        testWidgets('fits 2x in $locale: ${kind.name}', (tester) async {
          await _pump(
            tester,
            kind,
            locale: locale,
            textScaler: const TextScaler.linear(2),
          );

          final copy = _copy(tester, kind);
          for (final text in [copy.what, copy.rule, copy.source, copy.ours]) {
            expect(text, isNot(contains('{')));
          }
        });
      }
    }
  });
}
