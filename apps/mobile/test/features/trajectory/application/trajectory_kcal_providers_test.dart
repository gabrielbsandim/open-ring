import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/trajectory/application/trajectory_kcal_providers.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';

import '../presentation/trajectory_screen_fixtures.dart';

// Resting 1725 with the 10 percent margin steps to 1550 and 1900.
const _prototypeDay = EnergyDayEstimate(
  resting: 1725,
  base: 1725,
  steps: 200,
  workouts: 0,
);

Goal _goal({
  GoalPhase phase = GoalPhase.block,
  double? blockAnchorKg = 80,
  LocalDate blockStartedOn = november,
}) => Goal(
  id: 1,
  kind: GoalKind.loseFat,
  pace: null,
  startedOn: blockStartedOn,
  anchorKg: 80,
  referenceKg: null,
  blockStartedOn: blockStartedOn,
  blockAnchorKg: blockAnchorKg,
  phase: phase,
  phaseSince: blockStartedOn,
  phaseUntil: null,
  levers: const [],
  endedOn: null,
  endReason: null,
);

ProviderContainer _container({
  EnergyGate gate = EnergyGate.on,
  TrajectoryView? view,
  EnergyDay day = _prototypeDay,
  WeightSummary? summary,
  Goal? goal,
}) => ProviderContainer.test(
  overrides: [
    clockProvider.overrideWithValue(
      () => DateTime(november.year, november.month, november.day, 12),
    ),
    energyGateProvider.overrideWithValue(gate),
    trajectoryViewProvider.overrideWith((ref) async => view ?? readyView()),
    energyTodayProvider.overrideWith((ref) async => day),
    weightSummaryProvider.overrideWith(
      (ref) async => summary ?? summaryEnding(november),
    ),
    activeGoalProvider.overrideWith((ref) async => goal),
  ],
);

Future<KcalReady> _ready(ProviderContainer container) async {
  final kcal = await container.read(trajectoryKcalProvider.future);
  expect(kcal, isA<KcalReady>());
  return kcal as KcalReady;
}

void main() {
  group('TR10a acceptance 1: the Energy gate must be on', () {
    for (final gate in [
      EnergyGate.off,
      EnergyGate.underage,
      EnergyGate.hidden,
    ]) {
      test('${gate.name} gives KcalOff', () async {
        final container = _container(gate: gate);

        expect(
          await container.read(trajectoryKcalProvider.future),
          isA<KcalOff>(),
        );
      });
    }

    test('on gives KcalReady', () async {
      final container = _container();

      expect(
        await container.read(trajectoryKcalProvider.future),
        isA<KcalReady>(),
      );
    });
  });

  group('TR10a acceptance 2: the prototype numbers', () {
    test('resting burn reads 1550 to 1900', () async {
      final kcal = await _ready(_container());

      expect(kcal.resting, (low: 1550, high: 1900));
    });

    test(
      'trend 77.6 and 12 week middle 73.9 give 40 at rest, 90 a day',
      () async {
        final kcal = await _ready(_container());

        expect(kcal.restChange12!.abs(), 40);
        expect(kcal.dayChange12!.abs(), 90);
        expect(kcal.restChange12, lessThan(0));
        expect(kcal.dayChange12, lessThan(0));
      },
    );

    test('a gaining trend flips the sign of both changes', () async {
      final view = readyView(
        rate: const WeightRateReady(perWeek: 0.3, low: 0.2, high: 0.4),
        band: const ScenarioBand(days: 84, low: 77, mid: 81.3, high: 82),
      );
      final kcal = await _ready(_container(view: view));

      expect(kcal.restChange12, 40);
      expect(kcal.dayChange12, 90);
    });
  });

  group('TR10a review focus: sex missing', () {
    test('no resting row, the rest of the card is still there', () async {
      final kcal = await _ready(
        _container(day: const EnergyDayMissing({EnergyField.sex})),
      );

      expect(kcal.resting, isNull);
      expect(kcal.dayChange12!.abs(), 90);
      expect(kcal.balance, isA<EnergyBalanceReady>());
    });
  });

  group('TR10a review focus: band middle floored', () {
    test('the changes follow ready.band.mid, not low or high', () async {
      final view = readyView(
        band: const ScenarioBand(days: 84, low: 72.6, mid: 74.6, high: 75.1),
      );
      final kcal = await _ready(_container(view: view));

      expect(kcal.restChange12!.abs(), 30);
      expect(kcal.dayChange12!.abs(), 70);
    });
  });

  group('TR10a acceptance 3: each balance state', () {
    test(
      '28 days of weigh-ins and a losing rate give a stepped range',
      () async {
        final kcal = await _ready(_container());

        final balance = kcal.balance as EnergyBalanceReady;
        expect(balance.shown, (low: -450, high: -300));
        expect(balance.balanced, isFalse);
        expect(balance.weighIns, 28);
      },
    );

    test('a range that spans zero is balanced', () async {
      final kcal = await _ready(_container(view: readyView(rate: stableRate)));

      final balance = kcal.balance as EnergyBalanceReady;
      expect(balance.balanced, isTrue);
    });

    test('19 weigh-ins in 28 days give the count', () async {
      final dates = [
        for (var age = 18; age >= 0; age--) november.addDays(-age),
      ];
      final kcal = await _ready(_container(summary: summaryOn(dates)));

      expect(kcal.balance, isA<EnergyBalanceCount>());
      expect((kcal.balance as EnergyBalanceCount).weighIns, 19);
    });

    test('20 weigh-ins in 28 days are enough', () async {
      final dates = [
        for (var age = 19; age >= 0; age--) november.addDays(-age),
      ];
      final kcal = await _ready(_container(summary: summaryOn(dates)));

      expect(kcal.balance, isA<EnergyBalanceReady>());
    });

    test('a block started 40 days ago waits until day 41', () async {
      final start = november.addDays(-40);
      final kcal = await _ready(_container(goal: _goal(blockStartedOn: start)));

      expect(kcal.balance, isA<EnergyBalanceBlock>());
      expect((kcal.balance as EnergyBalanceBlock).from, start.addDays(41));
    });

    test('a block started 41 days ago no longer waits', () async {
      final start = november.addDays(-41);
      final kcal = await _ready(_container(goal: _goal(blockStartedOn: start)));

      expect(kcal.balance, isA<EnergyBalanceReady>());
    });
  });

  group('TR10a review focus: goal block start outside the block phase', () {
    for (final phase in [GoalPhase.maintenance, GoalPhase.paused]) {
      test('${phase.name} does not hold the balance', () async {
        final goal = _goal(phase: phase, blockStartedOn: november.addDays(-5));
        final kcal = await _ready(_container(goal: goal));

        expect(kcal.balance, isA<EnergyBalanceReady>());
      });
    }

    test(
      'a block without an anchor weight does not hold the balance',
      () async {
        final goal = _goal(
          blockAnchorKg: null,
          blockStartedOn: november.addDays(-5),
        );
        final kcal = await _ready(_container(goal: goal));

        expect(kcal.balance, isA<EnergyBalanceReady>());
      },
    );

    test('a block with an anchor weight holds the balance', () async {
      final goal = _goal(blockStartedOn: november.addDays(-5));
      final kcal = await _ready(_container(goal: goal));

      expect(kcal.balance, isA<EnergyBalanceBlock>());
    });
  });
}
