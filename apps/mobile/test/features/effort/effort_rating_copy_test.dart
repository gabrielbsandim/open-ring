import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/effort/presentation/effort_evidence_sheet.dart';
import 'package:open_ring/features/effort/presentation/effort_formula_screen.dart';
import 'package:open_ring/features/effort/presentation/effort_screen.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';

import '../../helpers/ble_fakes.dart';
import '../../helpers/layout_harness.dart';
import '../../helpers/ring_fakes.dart';
import '../../helpers/workout_fakes.dart';

final _divisor = RegExp(
  '(?<!\\d)${effortRatingDivisor.toStringAsFixed(0)}(?!\\d)',
);

WorkoutListItem _entry({int? rating}) => WorkoutListItem(
  id: 1,
  type: WorkoutType.running,
  start: workoutStart,
  end: workoutStart.add(const Duration(minutes: 40)),
  utcOffset: Duration.zero,
  elapsed: const Duration(minutes: 40),
  rating: rating,
);

List<BpmSample> _hardHeartRate() => [
  for (var i = 0; i <= 240; i++)
    (at: workoutStart.add(Duration(seconds: i * 10)), bpm: 175),
];

Future<MetricFormat> _format(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
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
    brightness: Brightness.dark,
    locale: locale,
    overrides: [...bleOverrides(), ...ringOverrides()],
  );
  return format;
}

Future<void> _pumpFormula(WidgetTester tester, Locale locale) => pumpScaled(
  tester,
  screenHost(const EffortFormulaScreen()),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: locale,
  overrides: [
    ...bleOverrides(),
    ...ringOverrides(),
    moduleStoreProvider.overrideWithValue(
      InMemoryModuleStore(const {ModuleId.effort}),
    ),
  ],
);

String _formulaLoad(WidgetTester tester) {
  final card = find.byKey(EffortFormulaKeys.load);
  final texts = find.descendant(of: card, matching: find.byType(Text));
  return [for (final text in tester.widgetList<Text>(texts)) text.data ?? '']
      .join(' ');
}

void main() {
  group('the sheet of a rated session names the rating', () {
    testWidgets('the rating, the minutes and the load', (tester) async {
      final format = await _format(tester);
      final l10n = format.l10n;
      final session = effortSessionOf(_entry(rating: 7));

      expect(session.load.source, LoadSource.rating);
      expect(session.load.value, 140);
      expect(
        effortSessionYours(format, session),
        l10n.effortSheetSessionYoursRating(
          WorkoutType.running.label(l10n),
          'Tue',
          '40',
          '7',
          '140',
        ),
      );
    });

    testWidgets('a rating under the heart rate figure changes nothing', (
      tester,
    ) async {
      final format = await _format(tester);
      final l10n = format.l10n;
      final session = effortSessionOf(
        _entry(rating: 1),
        heartRate: _hardHeartRate(),
        zones: HeartRateZones(maxHeartRate: 190),
      );

      expect(session.load.source, LoadSource.heartRate);
      expect(
        effortSessionYours(format, session),
        l10n.effortSheetSessionYoursHeartRate(
          WorkoutType.running.label(l10n),
          'Tue',
          '40',
          '${session.load.value}',
        ),
      );
    });

    testWidgets('a session with neither names the default and the rating', (
      tester,
    ) async {
      final format = await _format(tester);
      final l10n = format.l10n;
      final session = effortSessionOf(_entry());

      final yours = effortSessionYours(format, session);

      expect(session.load.source, LoadSource.typeDefault);
      expect(
        yours,
        l10n.effortSheetSessionYoursDefault(
          WorkoutType.running.label(l10n),
          'Tue',
          '40',
          '120',
          '3',
        ),
      );
      expect(yours, contains('rating'));
    });

    for (final locale in AppLocales.supported) {
      testWidgets('the rated sentence has no hole in $locale', (tester) async {
        final format = await _format(tester, locale: locale);
        final yours = effortSessionYours(
          format,
          effortSessionOf(_entry(rating: 7)),
        );

        expect(yours, isNot(contains('{')));
        expect(yours, contains('7'));
        expect(yours, contains('140'));
        expect(yours, contains('40'));
      });
    }
  });

  group('the rule says minutes times rating over the divisor', () {
    testWidgets('the session sheet, in English', (tester) async {
      final copy = effortEvidenceCopy(
        await _format(tester),
        EffortEvidence.session,
      );
      final rule = copy.rule.toLowerCase();

      expect(rule, contains('rating'));
      expect(rule, contains('larger'));
      expect(copy.rule, contains(_divisor));
    });

    testWidgets('the formula screen, in English', (tester) async {
      await _pumpFormula(tester, const Locale('en'));
      await tester.scrollUntilVisible(
        find.byKey(EffortFormulaKeys.load),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final load = _formulaLoad(tester);

      expect(load.toLowerCase(), contains('rating'));
      expect(load.toLowerCase(), contains('larger'));
      expect(load, contains(_divisor));
    });

    for (final locale in AppLocales.supported) {
      testWidgets('the divisor is in the session rule in $locale', (
        tester,
      ) async {
        final copy = effortEvidenceCopy(
          await _format(tester, locale: locale),
          EffortEvidence.session,
        );

        expect(copy.rule, contains(_divisor));
        expect(copy.rule, isNot(contains('{')));
      });

      testWidgets('the divisor is in the formula load part in $locale', (
        tester,
      ) async {
        await _pumpFormula(tester, locale);
        await tester.scrollUntilVisible(
          find.byKey(EffortFormulaKeys.load),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        final load = _formulaLoad(tester);

        expect(load, contains(_divisor));
        expect(load, isNot(contains('{')));
      });
    }
  });

  group('no shipped text still denies the rating', () {
    testWidgets('the English copy that the stored rating falsifies moved', (
      tester,
    ) async {
      final l10n = (await _format(tester)).l10n;

      expect(
        l10n.effortSheetSessionOurs,
        isNot(
          'The default of each type of workout, used when a session has no '
          'heart rate zones.',
        ),
      );
      expect(
        l10n.effortFormulaCannot1,
        isNot(
          'A ring on the finger loses the pulse when you grip a bar, so a '
          'strength session often counts by its type.',
        ),
      );
      expect(
        l10n.effortFoot,
        isNot(
          'Points and loads are recalculated from your workouts, your steps '
          'and your readiness. Estimate, not a medical assessment.',
        ),
      );
      expect(
        l10n.effortFormulaOurs3('1.5'),
        isNot('The type defaults and the 1.5 for brisk walking.'),
      );
    });

    testWidgets('the Foster source line carries its caveat', (tester) async {
      final sheet = effortEvidenceCopy(
        await _format(tester),
        EffortEvidence.session,
      ).source;
      await _pumpFormula(tester, const Locale('en'));
      await tester.scrollUntilVisible(
        find.byKey(EffortFormulaKeys.sources),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final sources = find.descendant(
        of: find.byKey(EffortFormulaKeys.sources),
        matching: find.byType(Text),
      );
      final formula = [
        for (final text in tester.widgetList<Text>(sources)) text.data ?? '',
      ].join(' ');

      final named = [sheet, formula].where((t) => t.contains('Foster'));
      expect(named, isNotEmpty);
      expect(named, everyElement(contains('still to be checked')));
    });
  });
}
