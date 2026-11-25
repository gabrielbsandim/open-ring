import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/food/application/food_energy.dart';
import 'package:open_ring/features/food/application/food_energy_gate.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/food_energy_store.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/domain/meal_analysis_store.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/presentation/food_energy_screen.dart';
import 'package:open_ring/features/food/presentation/food_energy_sheet.dart';
import 'package:open_ring/features/food/presentation/food_energy_views.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';

import '../../../helpers/layout_harness.dart';
import '../food_fakes.dart';

const _title = 'Weekly energy';
const _lead =
    'One range a week, from the meals you checked and your weight trend. '
    "Never for a meal, never a day's total.";
const _never =
    "Never shows the calories of a meal or a day's total. Never a budget, a "
    'calorie target or what is left. Never on Today, in a widget or in a '
    'notification.';
const _first =
    'The first range needs 28 of the last 35 days with checked items and 20 '
    'weigh-ins, so it comes after 4 weeks at the earliest.';
const _screenedOn = LocalDate(2026, 11, 20);
const _sunday = LocalDate(2026, 12, 6);

const _counts = FoodEnergyCounts(
  sunday: _sunday,
  days: 12,
  weekDays: 4,
  weighIns: 9,
  ringDays: 30,
);
final _ready = FoodEnergyReady(
  _counts,
  foodEnergyFigures(
    slopeKgPerDay: -0.03,
    logMean: 1780,
    weekMean: 1700,
    previousMean: 1800,
    ringMean: 2500,
  ),
);

final class CountingEnergyStore implements FoodEnergyStore {
  new([this.optIn]);

  FoodEnergyOptIn? optIn;
  int writes = 0;
  int clears = 0;

  @override
  Future<FoodEnergyOptIn?> read() async => optIn;

  @override
  Future<void> write(FoodEnergyOptIn value) async {
    writes++;
    optIn = value;
  }

  @override
  Future<void> clear() async {
    clears++;
    optIn = null;
  }
}

Future<CountingEnergyStore> _pump(
  WidgetTester tester,
  FoodEnergyGate gate, {
  FoodEnergyResult? result,
  double scale = 1,
  List<Override>? data,
}) async {
  final store = CountingEnergyStore();
  await pumpScaled(
    tester,
    screenHost(const FoodEnergyScreen()),
    textScaler: TextScaler.linear(scale),
    brightness: Brightness.dark,
    locale: const Locale('en'),
    size: const Size(360, 2400),
    overrides: [
      clockProvider.overrideWithValue(() => DateTime(2026, 12, 8, 12)),
      ...data ??
          [
            foodEnergyProvider.overrideWith(
              (ref) async => FoodEnergyView(gate: gate, result: result),
            ),
          ],
      foodEnergyGateProvider.overrideWith((ref) async => gate),
      foodEnergyStoreProvider.overrideWithValue(store),
      demoModeStoreProvider.overrideWithValue(
        InMemoryDemoModeStore(enabled: gate is FoodEnergyDemo),
      ),
      goalStoreProvider.overrideWithValue(InMemoryGoalStore()),
    ],
  );
  await tester.pumpAndSettle();
  return store;
}

final class _NoAnalyses implements MealAnalysisStore {
  @override
  Future<Map<int, List<MealAnalysis>>> byMeals(Set<int> mealIds) async => {};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected: ${invocation.memberName}');
}

final class _UntouchedMeals implements MealStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected: ${invocation.memberName}');
}

final class _UntouchedAnalyses implements MealAnalysisStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected: ${invocation.memberName}');
}

void _sees(List<String> texts) {
  for (final text in texts) {
    expect(find.text(text), findsOneWidget, reason: text);
  }
}

void _needRows({required String weighIns, required String days}) {
  _sees([
    'AI analysis on',
    'Body on',
    'Goals questions answered',
    'Weigh-ins in the last 35 days',
    'Days with checked items in the last 35 days',
    weighIns,
    days,
  ]);
}

const _screenFirst =
    'It uses the same five questions as a weight goal. Answer them '
    'first. Only the result and the date are kept.';

const _offBody =
    'When it is on, the photos you analyze ask for one more step: '
    'check the items in household measures and mark what the '
    'camera cannot see. Once a week a range comes out.';

const _switchLine =
    'Turning it off keeps the checked items. They just stop becoming '
    'a range.';

const _text3 =
    'Needs the Body module: the arithmetic compares your log with the '
    'scale over 5 weeks.';

const _text4 =
    'Off while Goals soft mode is on. Food keeps the diary, the times '
    'and the comparisons.';

const _text5 =
    'Needs Female or Male in your profile, for the expenditure '
    'estimate.';

void main() {
  // Each state renders at 1x and 2x text with no overflow: the layout golden.
  for (final scale in [1.0, 2.0]) {
    group('at ${scale}x text', () {
      testWidgets('hidden is an empty page with the title', (tester) async {
        await _pump(tester, const FoodEnergyHidden(), scale: scale);

        _sees([_title]);
        expect(find.text(_lead), findsNothing);
        expect(find.byKey(FoodEnergyKeys.toggle), findsNothing);
      });

      testWidgets('demo shows the labelled F1 sample, no switch and no '
          'store call', (tester) async {
        final store = await _pump(
          tester,
          const FoodEnergyDemo(),
          scale: scale,
          data: [
            mealStoreProvider.overrideWithValue(_UntouchedMeals()),
            mealAnalysisStoreProvider.overrideWithValue(_UntouchedAnalyses()),
          ],
        );

        _sees([
          _title,
          _lead,
          _never,
          'Sample with invented numbers. Nothing of yours was used.',
          'Nov 30 to Dec 6',
          '1,800 to 2,450 kcal a day, on average',
          '5% to 30% under',
          'No clear difference',
        ]);
        expect(find.byKey(FoodEnergyViewKeys.rangeCard), findsOneWidget);
        expect(find.byKey(FoodEnergyKeys.toggle), findsNothing);
        expect(find.byKey(FoodEnergyKeys.turnOn), findsNothing);
        expect(store.writes + store.clears, 0);
      });

      testWidgets('needs screening asks for the five questions', (
        tester,
      ) async {
        await _pump(tester, const FoodEnergyNeedsScreening(), scale: scale);

        _sees([_lead, _screenFirst, 'Answer the five questions']);
      });

      testWidgets('offered lists the needs and the turn on button', (
        tester,
      ) async {
        await _pump(
          tester,
          const FoodEnergyOffered(_screenedOn),
          result: const FoodEnergyHold(_counts, FoodEnergyHoldReason.weighIns),
          scale: scale,
        );

        _sees(['Off', _offBody, 'Turn on Weekly energy', _first, _never]);
        _needRows(weighIns: '9 of 20', days: '12 of 28');
        expect(find.byKey(FoodEnergyKeys.toggle), findsNothing);
      });

      testWidgets('on and building shows the counts and the switch', (
        tester,
      ) async {
        await _pump(
          tester,
          const FoodEnergyOn(_screenedOn),
          result: const FoodEnergyHold(_counts, FoodEnergyHoldReason.days),
          scale: scale,
        );

        _needRows(weighIns: '9 of 20', days: '12 of 28');
        _sees([_first, _switchLine]);
        expect(find.byKey(FoodEnergyKeys.turnOn), findsNothing);
      });

      testWidgets('on with a range shows the range views and the switch', (
        tester,
      ) async {
        await _pump(
          tester,
          const FoodEnergyOn(_screenedOn),
          result: _ready,
          scale: scale,
        );

        expect(find.byKey(FoodEnergyViewKeys.rangeCard), findsOneWidget);
        expect(find.byKey(FoodEnergyViewKeys.gapCard), findsOneWidget);
        expect(find.byKey(FoodEnergyViewKeys.mathCard), findsOneWidget);
        expect(find.byKey(FoodEnergyViewKeys.limits), findsOneWidget);
        expect(find.byKey(FoodEnergyViewKeys.sample), findsNothing);
        _sees(['1,800 to 2,450 kcal a day, on average', _switchLine]);
        expect(find.byKey(FoodEnergyKeys.toggle), findsOneWidget);
        expect(find.byKey(FoodEnergyKeys.building), findsNothing);
        expect(find.text(_first), findsNothing);
      });

      testWidgets('on and holding with a last range shows the hold and the '
          'switch', (tester) async {
        await _pump(
          tester,
          const FoodEnergyOn(_screenedOn),
          result: FoodEnergyHold(
            _counts,
            FoodEnergyHoldReason.modelChanged,
            last: _ready,
          ),
          scale: scale,
        );

        expect(find.byKey(FoodEnergyViewKeys.holdCard), findsOneWidget);
        expect(find.byKey(FoodEnergyViewKeys.lastRange), findsOneWidget);
        expect(find.byKey(FoodEnergyViewKeys.rangeCard), findsNothing);
        _sees(['No new range this week', 'Last range, Nov 30 to Dec 6']);
        expect(find.byKey(FoodEnergyKeys.toggle), findsOneWidget);
        expect(find.byKey(FoodEnergyKeys.building), findsNothing);
      });
    });
  }

  group('blocked', () {
    const lines = {
      FoodEnergyBlock.bodyOff: _text3,
      FoodEnergyBlock.softMode: _text4,
      FoodEnergyBlock.under18: 'Not offered under 18.',
      FoodEnergyBlock.bmiUnderFloor: 'Not offered with a BMI under 18.5.',
      FoodEnergyBlock.pregnancy:
          'Not offered in pregnancy or while breastfeeding.',
      FoodEnergyBlock.ageMissing:
          'Needs your birth year, for the expenditure estimate.',
      FoodEnergyBlock.heightMissing:
          'Needs your height, for the expenditure estimate.',
      FoodEnergyBlock.sexMissing: _text5,
    };
    const actions = {
      FoodEnergyBlock.bodyOff: 'Open Body',
      FoodEnergyBlock.ageMissing: 'Open Settings',
      FoodEnergyBlock.heightMissing: 'Open Settings',
      FoodEnergyBlock.sexMissing: 'Open Settings',
    };
    for (final block in FoodEnergyBlock.values) {
      testWidgets('${block.name} renders its line and action', (tester) async {
        await _pump(tester, FoodEnergyBlocked(block), scale: 2);

        _sees([_lead, lines[block]!]);
        final action = actions[block];
        expect(
          find.byKey(FoodEnergyKeys.blockedAction),
          action == null ? findsNothing : findsOneWidget,
        );
        if (action != null) _sees([action]);
        expect(find.byKey(FoodEnergyKeys.toggle), findsNothing);
      });
    }
  });

  testWidgets('turning on from offered writes once and confirms', (
    tester,
  ) async {
    final store = await _pump(tester, const FoodEnergyOffered(_screenedOn));

    await tester.tap(find.byKey(FoodEnergyKeys.turnOn));
    await tester.pumpAndSettle();
    expect(find.byKey(FoodEnergySheetKeys.sheet), findsOneWidget);
    await tester.tap(find.byKey(FoodEnergySheetKeys.on));
    await tester.pumpAndSettle();

    expect(store.writes, 1);
    expect(store.optIn?.on, const LocalDate(2026, 12, 8));
    expect(find.byKey(FoodEnergySheetKeys.sheet), findsNothing);
    expect(find.text('Weekly energy on.'), findsOneWidget);
  });

  testWidgets('cancel in the sheet writes nothing', (tester) async {
    final store = await _pump(tester, const FoodEnergyOffered(_screenedOn));

    await tester.tap(find.byKey(FoodEnergyKeys.turnOn));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FoodEnergySheetKeys.cancel));
    await tester.pumpAndSettle();

    expect(store.writes, 0);
    expect(find.text('Weekly energy on.'), findsNothing);
  });

  testWidgets('the switch turns it off at once and keeps the items', (
    tester,
  ) async {
    final store = await _pump(
      tester,
      const FoodEnergyOn(_screenedOn),
      result: _ready,
    );

    await tester.tap(find.byKey(FoodEnergyKeys.toggle));
    await tester.pumpAndSettle();

    expect(store.clears, 1);
    expect(store.writes, 0);
    expect(
      find.text('Weekly energy off. The checked items stay saved.'),
      findsOneWidget,
    );
  });

  group('a failed data read keeps the controls', () {
    const failingDay = LocalDate(2026, 11, 20);

    List<Override> reads({bool weighInsFail = false}) => [
      mealStoreProvider.overrideWithValue(TestMealStore()),
      mealAnalysisStoreProvider.overrideWithValue(_NoAnalyses()),
      weighInsProvider.overrideWith((ref) async {
        if (weighInsFail) throw StateError('weigh-in read');
        return const [];
      }),
      energyDayProvider.overrideWith((ref, date) async {
        if (date == failingDay) throw StateError('ring read');
        return const EnergyDayEstimate(
          resting: 1500,
          base: 2000,
          steps: 500,
          workouts: 0,
        );
      }),
      activeGoalProvider.overrideWith((ref) async => null),
    ];

    testWidgets('offered with a throwing weigh-in read still turns on', (
      tester,
    ) async {
      final store = await _pump(
        tester,
        const FoodEnergyOffered(_screenedOn),
        data: reads(weighInsFail: true),
      );

      expect(find.text('Weigh-ins in the last 35 days'), findsOneWidget);
      expect(find.textContaining(' of 20'), findsNothing);
      expect(find.text('Off'), findsOneWidget);
      await tester.tap(find.byKey(FoodEnergyKeys.turnOn));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(FoodEnergySheetKeys.on));
      await tester.pumpAndSettle();

      expect(store.writes, 1);
      expect(find.text('Weekly energy on.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('on with one throwing ring day still shows the switch', (
      tester,
    ) async {
      await _pump(tester, const FoodEnergyOn(_screenedOn), data: reads());

      expect(find.byKey(FoodEnergyKeys.toggle), findsOneWidget);
      expect(find.textContaining('Could not read'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
