import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/presentation/goal_evidence_sheet.dart';
import 'package:open_ring/features/trajectory/application/trajectory_kcal_providers.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_screen.dart';
import 'package:open_ring/features/trajectory/presentation/what_if_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../support/what_if_fixtures.dart';
import 'trajectory_screen_fixtures.dart';

const _en = Locale('en');
const _tall = Size(360, 4000);
const _defaultLayout = LayoutCase(
  scale: 1,
  brightness: Brightness.light,
  locale: _en,
);

AppLocalizations get _l10n => lookupAppLocalizations(_en);

KcalReady _kcal(EnergyBalance balance) => KcalReady(
  resting: (low: 1550, high: 1900),
  restChange12: -40,
  dayChange12: -90,
  balance: balance,
);

const _ready = EnergyBalanceReady(
  low: -473,
  mid: -385,
  high: -286,
  weighIns: 25,
);

Future<void> _pumpTrajectory(
  WidgetTester tester, {
  required TrajectoryKcal kcal,
  LayoutCase layout = _defaultLayout,
}) => pumpScaled(
  tester,
  screenHost(const TrajectoryScreen()),
  textScaler: layout.textScaler,
  brightness: layout.brightness,
  locale: layout.locale,
  size: _tall,
  overrides: [
    ...trajectoryOverrides(view: readyView()),
    energyGateProvider.overrideWithValue(EnergyGate.on),
    energyTodayProvider.overrideWith(
      (ref) async => const EnergyDayEstimate(
        resting: 1725,
        base: 1725,
        steps: 200,
        workouts: 0,
      ),
    ),
    activeGoalProvider.overrideWith((ref) async => null),
    trajectoryKcalProvider.overrideWith((ref) async => kcal),
  ],
);

Future<void> _pumpWhatIf(
  WidgetTester tester, {
  double typical = 8700,
  bool hidden = false,
  EnergyGate gate = EnergyGate.on,
  LayoutCase layout = _defaultLayout,
}) => pumpScaled(
  tester,
  screenHost(const WhatIfScreen()),
  textScaler: layout.textScaler,
  brightness: layout.brightness,
  locale: layout.locale,
  size: _tall,
  overrides: whatIfOverrides(typical: typical, hidden: hidden, gate: gate),
);

Future<void> _openText(WidgetTester tester, String text) async {
  final target = find.text(text).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _openKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

String _sheetText(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(GoalEvidenceKeys.sheet),
      matching: find.byType(Text),
    ),
  ))
    text.data ?? text.textSpan?.toPlainText() ?? '',
].join(' | ');

String _yours(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(GoalEvidenceKeys.yours),
      matching: find.byType(Text),
    ),
  ))
    text.data ?? text.textSpan?.toPlainText() ?? '',
].join(' ');

void main() {
  group('kcal sheets', () {
    testWidgets('resting row shows the range and the 10% band', (tester) async {
      await _pumpTrajectory(tester, kcal: _kcal(_ready));
      await _openText(tester, _l10n.trajectoryKcalResting);

      expect(_yours(tester), contains('1,550 to 1,900 kcal a day'));
      expect(_yours(tester), contains('10% each side'));
      expect(_sheetText(tester), contains('Mifflin'));
    });

    testWidgets('scenario row shows both per kg products', (tester) async {
      await _pumpTrajectory(tester, kcal: _kcal(_ready));
      await _openText(tester, _l10n.trajectoryKcalScenario);

      final yours = _yours(tester);
      expect(yours, contains('3.7 kg below'));
      expect(yours, contains('9.99 kcal per kg × 3.70 = about 40 kcal'));
      expect(yours, contains('24 × 3.70 = about 90'));
    });

    testWidgets('a ready balance shows the 7,700 math with both ends', (
      tester,
    ) async {
      await _pumpTrajectory(tester, kcal: _kcal(_ready));
      await _openText(tester, _l10n.trajectoryKcalBalance);

      final yours = _yours(tester);
      expect(yours, contains('× 7,700: -385 kcal a day'));
      expect(yours, contains('from -473 to -286'));
      expect(yours, contains('25 weigh-ins'));
    });

    for (final (name, balance, expected) in [
      ('no rate', const EnergyBalanceNoRate(), 'Needs 4 weeks'),
      ('count', const EnergyBalanceCount(12), 'So far: 12'),
      (
        'block',
        const EnergyBalanceBlock(LocalDate(2026, 11, 30)),
        'from Nov 30',
      ),
    ]) {
      testWidgets('balance $name has its own number', (tester) async {
        await _pumpTrajectory(tester, kcal: _kcal(balance));
        await _openText(tester, _l10n.trajectoryKcalBalance);

        expect(_yours(tester), contains(expected));
        expect(_yours(tester), isNot(contains('7,700')));
      });
    }
  });

  group('what if sheets', () {
    testWidgets('weight row with Energy on shows km, kcal and the weeks', (
      tester,
    ) async {
      await _pumpWhatIf(tester);
      await _openKey(tester, WhatIfKeys.weight);

      final yours = _yours(tester);
      expect(yours, contains('1.48 km'));
      expect(yours, contains('kcal a day'));
      expect(yours, contains('In 12: 0.49 kg'));
    });

    testWidgets('weight row with Energy off never shows kcal', (tester) async {
      await _pumpWhatIf(tester, gate: EnergyGate.off);
      await _openKey(tester, WhatIfKeys.weight);

      expect(_yours(tester), contains('In 12: 0.49 kg'));
      expect(_sheetText(tester), isNot(contains('kcal')));
    });

    testWidgets('weight row with numbers hidden shows no values', (
      tester,
    ) async {
      await _pumpWhatIf(tester, hidden: true);
      await _openKey(tester, WhatIfKeys.weight);

      expect(_yours(tester), contains('No values while numbers are hidden'));
      expect(_sheetText(tester), isNot(contains('kg')));
      expect(_sheetText(tester), isNot(contains('kcal')));
    });

    testWidgets('cohort row shows hazards, ratio and words', (tester) async {
      await _pumpWhatIf(tester);
      await _openKey(tester, WhatIfKeys.cohort);

      final yours = _yours(tester);
      expect(yours, contains('From 8,700 to 10,700 steps'));
      expect(yours, contains('9.8% lower'));
      expect(yours, contains(_l10n.trajectoryWhatIfWordsSlightly));
      expect(yours, isNot(contains('no further gain')));
    });

    testWidgets('a clamped cohort adds the clamp line', (tester) async {
      await _pumpWhatIf(tester, typical: 9500);
      await _openKey(tester, WhatIfKeys.cohort);

      expect(_yours(tester), contains('no further gain'));
    });
  });

  group('no overflow', () {
    for (final layout in layoutMatrix()) {
      testWidgets('balance sheet at $layout', (tester) async {
        await _pumpTrajectory(tester, kcal: _kcal(_ready), layout: layout);
        await expectNoLayoutOverflow(
          () => _openText(
            tester,
            lookupAppLocalizations(layout.locale).trajectoryKcalBalance,
          ),
        );

        expect(find.byKey(GoalEvidenceKeys.sheet), findsOneWidget);
      });

      testWidgets('cohort sheet at $layout', (tester) async {
        await _pumpWhatIf(tester, layout: layout);
        await expectNoLayoutOverflow(() => _openKey(tester, WhatIfKeys.cohort));

        expect(find.byKey(GoalEvidenceKeys.sheet), findsOneWidget);
      });
    }
  });
}
