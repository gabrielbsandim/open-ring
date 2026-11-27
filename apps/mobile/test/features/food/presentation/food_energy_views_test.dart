import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/food/presentation/food_energy_views.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

const _sunday = LocalDate(2026, 12, 6);
const _counts = FoodEnergyCounts(
  sunday: _sunday,
  days: 30,
  weekDays: 6,
  weighIns: 28,
  ringDays: 35,
);

FoodEnergyReady _ready(
  double slope,
  double log,
  double week,
  double before,
  double ring, {
  FoodEnergyCounts counts = _counts,
}) => FoodEnergyReady(
  counts,
  foodEnergyFigures(
    slopeKgPerDay: slope,
    logMean: log,
    weekMean: week,
    previousMean: before,
    ringMean: ring,
  ),
);

final FoodEnergyReady _f1 = _ready(-0.03, 1780, 1700, 1800, 2500);
final FoodEnergyReady _f2 = _ready(-0.03, 1730, 1450, 1800, 2500);
final FoodEnergyReady _f4 = _ready(0, 2600, 2600, 2600, 2000);
final FoodEnergyReady _f5 = _ready(0, 2400, 2400, 2400, 2400);

Future<void> _pump(
  WidgetTester tester,
  Widget view, {
  Locale locale = const Locale('en'),
  bool weightHidden = false,
  double scale = 1,
}) => pumpScaled(
  tester,
  screenHost(Scaffold(body: ListView(children: [view]))),
  textScaler: TextScaler.linear(scale),
  brightness: Brightness.light,
  locale: locale,
  size: const Size(360, 2400),
  overrides: [profileWeightHiddenProvider.overrideWithValue(weightHidden)],
);

String _text(WidgetTester tester, Key key) {
  final widget = tester.widget(
    find.descendant(of: find.byKey(key), matching: find.byType(Text)).first,
  );
  return (widget as Text).data!;
}

Iterable<String> _texts(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? '',
];

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  // Each view renders at 1x and 2x text with no overflow: the layout golden.
  for (final scale in [1.0, 2.0]) {
    group('at ${scale}x text', () {
      testWidgets('F1 renders the range, the gap, the change and the '
          'arithmetic', (tester) async {
        await _pump(tester, FoodEnergyReadyView(_f1), scale: scale);

        expect(find.text('Nov 30 to Dec 6'), findsOneWidget);
        expect(find.text('range'), findsOneWidget);
        expect(
          find.text('1,800 to 2,450 kcal a day, on average'),
          findsOneWidget,
        );
        expect(find.text('Ring expenditure: 2,500 kcal a day'), findsOne);
        expect(
          _text(tester, FoodEnergyViewKeys.rangeNote),
          'Average of 6 days with checked items. It is a range, not a '
          'number: the low end and the high end are equally possible.',
        );
        expect(find.text('5% to 30% under'), findsOneWidget);
        expect(find.text('No clear difference'), findsOneWidget);
        expect(
          _text(tester, FoodEnergyViewKeys.changeNote),
          startsWith('The difference was between -290 and 40 kcal a day.'),
        );
        expect(find.text(en.overallSheetRule), findsOneWidget);
        expect(find.text(en.overallSheetLimits), findsOneWidget);
        expect(find.text(en.foodEnergyLimits), findsOneWidget);
        expect(find.text(en.foodEnergyMathNote('7,700')), findsOneWidget);
      });

      testWidgets('a hold shows its line and the muted last range', (
        tester,
      ) async {
        await _pump(
          tester,
          FoodEnergyHoldView(
            FoodEnergyHold(
              _counts,
              FoodEnergyHoldReason.modelChanged,
              last: _ready(
                -0.03,
                1780,
                1700,
                1800,
                2500,
                counts: const FoodEnergyCounts(
                  sunday: LocalDate(2026, 11, 29),
                  days: 30,
                  weekDays: 6,
                  weighIns: 28,
                  ringDays: 35,
                ),
              ),
            ),
          ),
          scale: scale,
        );

        expect(find.text('holding'), findsOneWidget);
        expect(find.text('No new range this week'), findsOneWidget);
        expect(
          find.text(
            'The analysis model or its answer format changed. It errs in a '
            'different direction, so the factor is learned again from 5 '
            'weeks of photos read the new way.',
          ),
          findsOneWidget,
        );
        expect(find.text('Last range, Nov 23 to Nov 29'), findsOneWidget);
        expect(
          find.text('1,800 to 2,450 kcal a day, on average'),
          findsOneWidget,
        );
      });
    });
  }

  testWidgets('F1 in pt formats the numbers with MetricFormat', (tester) async {
    await _pump(tester, FoodEnergyReadyView(_f1), locale: const Locale('pt'));

    expect(find.text('1.800 a 2.450 kcal por dia, em média'), findsOneWidget);
    expect(find.text('5% a 30% abaixo'), findsOneWidget);
    expect(find.text('Sem diferença clara'), findsOneWidget);
    expect(
      _text(tester, FoodEnergyViewKeys.changeNote),
      startsWith('A diferença ficou entre -290 e 40 kcal por dia.'),
    );
    expect(
      _text(tester, FoodEnergyViewKeys.mathWeight),
      contains('-0,030 × 7.700 = -231'),
    );
  });

  testWidgets('F2 is less, F4 is over and F5 has no clear gap', (tester) async {
    await _pump(tester, FoodEnergyReadyView(_f2));
    expect(find.text('1,550 to 2,150 kcal a day, on average'), findsOne);
    expect(find.text('8% to 32% under'), findsOneWidget);
    expect(find.text('Less'), findsOneWidget);
    expect(
      _text(tester, FoodEnergyViewKeys.changeNote),
      contains('between -660 and -230'),
    );

    await _pump(tester, FoodEnergyReadyView(_f4));
    expect(find.text('1,700 to 2,300 kcal a day, on average'), findsOne);
    expect(find.text('13% to 53% over'), findsOneWidget);
    expect(
      _text(tester, FoodEnergyViewKeys.changeNote),
      contains('between -150 and 150'),
    );

    await _pump(tester, FoodEnergyReadyView(_f5));
    expect(find.text('2,050 to 2,750 kcal a day, on average'), findsOne);
    expect(find.text('No clear gap'), findsOneWidget);
    expect(find.text('No clear difference'), findsOneWidget);
  });

  testWidgets('the weight lines show the slope and the balance', (
    tester,
  ) async {
    await _pump(tester, FoodEnergyReadyView(_f1));

    expect(
      _text(tester, FoodEnergyViewKeys.mathWeight),
      'weight line: -0.030 kg a day\n'
      'balance: -0.030 × 7,700 = -231 kcal a day',
    );
    expect(
      _text(tester, FoodEnergyViewKeys.math),
      'window: Nov 2 to Dec 6, 35 days\n'
      'weigh-ins: 28 · days with checked items: 30 of 35\n'
      'average log: 1,780 (log units)\n'
      'expenditure from the log: 1,780 minus the balance = 2,011\n'
      'ring expenditure: 2,500 ± 15%\n'
      'factor = ring ÷ log: 1.06 to 1.43\n'
      'week: 1,700 × 1.06 to × 1.43\n'
      '= 1,800 to 2,450 (rounded to 50)',
    );
  });

  testWidgets('hidden weight numbers drop the kg lines and keep the rest', (
    tester,
  ) async {
    await _pump(tester, FoodEnergyReadyView(_f1), weightHidden: true);

    expect(find.byKey(FoodEnergyViewKeys.mathWeight), findsNothing);
    expect(find.byKey(FoodEnergyViewKeys.math), findsOneWidget);
    expect(find.text('5% to 30% under'), findsOneWidget);
    expect(find.text('No clear difference'), findsOneWidget);
    for (final text in _texts(tester)) {
      expect(text, isNot(contains('kg')), reason: text);
    }
  });

  for (final reason in FoodEnergyHoldReason.values) {
    testWidgets('a ${reason.name} hold reads its own line', (tester) async {
      await _pump(tester, FoodEnergyHoldView(FoodEnergyHold(_counts, reason)));

      expect(find.text(en.foodEnergyHold(reason.name)), findsOneWidget);
      expect(find.byKey(FoodEnergyViewKeys.lastRange), findsNothing);
    });
  }

  test('each hold reason has its own line, implausible the other case', () {
    final lines = {
      for (final reason in FoodEnergyHoldReason.values)
        en.foodEnergyHold(reason.name),
    };
    expect(lines, hasLength(FoodEnergyHoldReason.values.length));
    expect(
      en.foodEnergyHold(FoodEnergyHoldReason.implausible.name),
      'The numbers of this window do not add up to a usable range.',
    );
  });

  test('the bar spans 50 to 130 percent of the ring mean, clamped', () {
    final f1 = foodEnergyBarSpan(_f1.figures);
    expect(f1.low, closeTo(0.275, 1e-9));
    expect(f1.high, closeTo(0.6, 1e-9));
    expect(f1.ring, closeTo(0.625, 1e-9));

    final wide = foodEnergyBarSpan(_ready(0, 1000, 3000, 1000, 1000).figures);
    expect(wide.low, 1);
    expect(wide.high, 1);
    final low = foodEnergyBarSpan(_ready(0, 4000, 1000, 4000, 1000).figures);
    expect(low.low, 0);
    expect(low.high, 0);
  });

  test('the demo sample is the F1 week of 2026-11-30 to 2026-12-06', () {
    expect(foodEnergySample.counts.sunday, _sunday);
    expect(foodEnergySample.figures.weekLow, 1800);
    expect(foodEnergySample.figures.weekHigh, 2450);
    expect(foodEnergySample.counts.weekDays, 6);
  });
}
