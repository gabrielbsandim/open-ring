import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/energy/presentation/energy_evidence_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

const EnergyDayEstimate _day = EnergyDayEstimate(
  resting: 1700,
  base: 1100,
  steps: 180,
  workouts: 304,
);

const EnergyDayEstimate _noWorkout = EnergyDayEstimate(
  resting: 1700,
  base: 1100,
  steps: 180,
  workouts: 0,
);

Future<void> _pump(
  WidgetTester tester,
  EnergyEvidence kind, {
  EnergyDayEstimate day = _day,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Brightness brightness = Brightness.dark,
}) => pumpScaled(
  tester,
  screenHost(
    Scaffold(
      body: EnergyEvidenceSheet(kind: kind, day: day),
    ),
  ),
  textScaler: textScaler,
  brightness: brightness,
  locale: locale,
  overrides: const [],
);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(EnergyEvidenceSheet)));

String _title(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(EnergyEvidenceKeys.title)).data!;

String _body(WidgetTester tester, Key key) => tester
    .widget<BodyText>(
      find.descendant(of: find.byKey(key), matching: find.byType(BodyText)),
    )
    .text;

Iterable<String> _allText(WidgetTester tester) sync* {
  for (final widget in tester.widgetList(find.byType(Text))) {
    yield (widget as Text).data ?? '';
  }
}

void main() {
  group('the resting burn', () {
    testWidgets('shows the range and never the exact figure', (tester) async {
      await _pump(tester, EnergyEvidence.resting);

      expect(_title(tester), _l10n(tester).energyRestingTitle);
      expect(
        _body(tester, EnergyEvidenceKeys.yours),
        '1,550 to 1,850 kcal a day, estimate',
      );
      expect(_allText(tester).any((text) => text.contains('1,700')), isFalse);
    });

    testWidgets('the rule prints the constants of the equation', (
      tester,
    ) async {
      await _pump(tester, EnergyEvidence.resting);
      final rule = _body(tester, EnergyEvidenceKeys.rule);

      for (final piece in [
        '9.99 ×',
        '6.25 ×',
        '4.92 ×',
        'plus 5 for men',
        'minus 161 for women',
        '10 percent',
        'nearest 50',
      ]) {
        expect(rule, contains(piece));
      }
      expect(
        _body(tester, EnergyEvidenceKeys.ours),
        _l10n(tester).energyOursResting('10'),
      );
    });
  });

  group('the parts', () {
    testWidgets('the Base says its factor and its value', (tester) async {
      await _pump(tester, EnergyEvidence.base);

      expect(_title(tester), _l10n(tester).energyPartBase);
      expect(_body(tester, EnergyEvidenceKeys.yours), 'about 1,100 kcal');
      expect(
        _body(tester, EnergyEvidenceKeys.rule),
        _l10n(tester).energyRuleBase('1.3'),
      );
    });

    testWidgets('the steps say the step length and the cost', (tester) async {
      await _pump(tester, EnergyEvidence.steps);

      expect(_title(tester), _l10n(tester).energyPartSteps);
      expect(_body(tester, EnergyEvidenceKeys.yours), 'about 180 kcal');
      expect(
        _body(tester, EnergyEvidenceKeys.rule),
        _l10n(tester).energyRuleSteps('0.415', '0.5'),
      );
    });

    testWidgets('the workouts say their value', (tester) async {
      await _pump(tester, EnergyEvidence.workouts);

      expect(_title(tester), _l10n(tester).energyPartWorkouts);
      expect(_body(tester, EnergyEvidenceKeys.yours), 'about 300 kcal');
    });

    testWidgets('a day without a workout says none was recorded', (
      tester,
    ) async {
      await _pump(tester, EnergyEvidence.workouts, day: _noWorkout);

      expect(
        _body(tester, EnergyEvidenceKeys.yours),
        _l10n(tester).energyPartWorkoutsNone,
      );
    });
  });

  group('every sheet', () {
    for (final kind in EnergyEvidence.values) {
      testWidgets('${kind.name} ends with the fixed note', (tester) async {
        await _pump(tester, kind);
        await tester.scrollUntilVisible(
          find.byKey(EnergyEvidenceKeys.note),
          100,
        );

        expect(
          tester.widget<CaptionText>(find.byKey(EnergyEvidenceKeys.note)).text,
          _l10n(tester).energyFixedNote,
        );
      });

      for (final locale in AppLocales.supported) {
        testWidgets('${kind.name} in $locale leaves no placeholder open', (
          tester,
        ) async {
          await _pump(tester, kind, locale: locale);

          for (final text in _allText(tester)) {
            expect(text, isNot(contains('{')));
            expect(text, isNot(contains('}')));
          }
        });
      }
    }
  });

  group('layout', () {
    for (final kind in EnergyEvidence.values) {
      for (final layout in layoutMatrix()) {
        testWidgets('${kind.name} fits $layout', (tester) async {
          await _pump(
            tester,
            kind,
            locale: layout.locale,
            textScaler: layout.textScaler,
            brightness: layout.brightness,
          );

          expect(find.byKey(EnergyEvidenceKeys.sheet), findsOneWidget);
        });
      }

      for (final locale in AppLocales.supported) {
        testWidgets('${kind.name} fits 2.0x in $locale', (tester) async {
          await _pump(
            tester,
            kind,
            locale: locale,
            textScaler: const TextScaler.linear(2),
          );

          expect(find.byKey(EnergyEvidenceKeys.sheet), findsOneWidget);
        });
      }
    }
  });
}
