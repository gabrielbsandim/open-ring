import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/review_inputs.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';

import '../goal_fixtures.dart';

const double _anchorKg = 80;
const double _closedKg = 71.9;
const double _openKg = 72.5;

// The block starts on 2026-11-16 and lasts 12 weeks, so it ends on 2027-02-07
// and the Monday after it is 2027-02-08.
LocalDate _day(int year, int month, int day) => LocalDate(year, month, day);

DateTime _at(int year, int month, int day) => DateTime(year, month, day, 8, 10);

GoalDraft _draft({GoalKind kind = GoalKind.loseFat}) => GoalDraft(
  kind: kind,
  pace: kind == GoalKind.loseFat ? GoalPace.standard : null,
  startedOn: _day(2026, 11, 16),
  anchorKg: kind == GoalKind.loseFat ? _anchorKg : null,
  referenceKg: kind == GoalKind.loseFat ? 70 : null,
  levers: const [strengthLever, sleepLever, stepsLever],
);

List<DailyValue> _flat(LocalDate last, double kg, {int days = 28}) => [
  for (var i = days - 1; i >= 0; i--) (date: last.addDays(-i), value: kg),
];

Override _weightOf(List<DailyValue> days) => weightSummaryProvider.overrideWith(
  (ref) async => goalWeightSummary(days: days),
);

Override _noWeight() => weightSummaryProvider.overrideWith((ref) async => null);

Override _throwingWeight() => weightSummaryProvider.overrideWith(
  (ref) async => throw StateError('the weight was read'),
);

Future<GoalSetup> _reviewing({
  required DateTime now,
  required Override weight,
  GoalKind kind = GoalKind.loseFat,
  Set<ModuleId> modules = goalModules,
}) => setupGoals(
  now: now,
  modules: modules,
  draft: _draft(kind: kind),
  weightOverride: weight,
);

Future<GoalSetup> _maintaining({
  required DateTime now,
  required LocalDate since,
  Override? weight,
}) async {
  final setup = await setupGoals(
    now: now,
    draft: _draft(),
    weightOverride: weight ?? _weightOf(_flat(since.addDays(-1), _closedKg)),
  );
  await setup.store.setPhase(
    1,
    GoalPhase.maintenance,
    since: since,
    until: since.addDays(27),
  );
  return setup;
}

ReviewInputs _inputs(
  ReviewInputs base, {
  CheckInEnergy? energy,
  CheckInEnergy? energyPrevious,
  bool maintenance = true,
}) => ReviewInputs(
  kind: base.kind,
  week: base.week,
  levers: base.levers,
  adherencePrevious: base.adherencePrevious,
  baseline: base.baseline,
  effortRaisesInRow: base.effortRaisesInRow,
  rate: base.rate,
  targetPercent: base.targetPercent,
  capPercent: base.capPercent,
  previousPercentLow: base.previousPercentLow,
  bmi: base.bmi,
  pregnantOrBreastfeeding: base.pregnantOrBreastfeeding,
  screeningPositive: base.screeningPositive,
  bodyOn: base.bodyOn,
  readiness: base.readiness,
  recoveryPrevious: base.recoveryPrevious,
  energy: energy,
  energyPrevious: energyPrevious,
  foodOrWeight: null,
  foodOrWeightPrevious: null,
  maintenance: maintenance,
);

Future<void> _addRow(
  GoalSetup setup,
  LocalDate monday,
  ReviewInputs inputs,
) async {
  final written = await setup.store.addWeek(
    1,
    monday: monday,
    inputs: inputs,
    review: reviewWeek(inputs),
  );
  expect(written, isTrue);
}

void main() {
  group('G11b1 criterion 1: the Monday after block.end closes the block', () {
    test('moves the goal into maintenance since that Monday', () async {
      final setup = await _reviewing(
        now: _at(2027, 2, 8),
        weight: _weightOf(_flat(_day(2027, 2, 7), _openKg)),
      );

      await setup.reviewer.reviewDueWeek();

      final goal = (await setup.store.active())!;
      expect(goal.phase, GoalPhase.maintenance);
      expect(goal.phaseSince, _day(2027, 2, 8));
    });

    test('keeps maintenance until the Monday plus 27 days', () async {
      final setup = await _reviewing(
        now: _at(2027, 2, 8),
        weight: _weightOf(_flat(_day(2027, 2, 7), _openKg)),
      );

      await setup.reviewer.reviewDueWeek();

      expect((await setup.store.active())!.phaseUntil, _day(2027, 3, 7));
    });

    test('writes the review of that Monday', () async {
      final setup = await _reviewing(
        now: _at(2027, 2, 8),
        weight: _weightOf(_flat(_day(2027, 2, 7), _openKg)),
      );

      await setup.reviewer.reviewDueWeek();

      final weeks = await setup.weeks();
      expect(weeks, hasLength(1));
      expect(weeks.single.monday, _day(2027, 2, 8));
    });

    test('the Monday before block.end leaves the block running', () async {
      final setup = await _reviewing(
        now: _at(2027, 2, 1),
        weight: _weightOf(_flat(_day(2027, 1, 31), _openKg)),
      );

      await setup.reviewer.reviewDueWeek();

      final goal = (await setup.store.active())!;
      expect(goal.phase, GoalPhase.block);
      expect(goal.phaseUntil, isNull);
    });

    test('a second pass on the same Monday does not move the window', () async {
      final setup = await _reviewing(
        now: _at(2027, 2, 8),
        weight: _weightOf(_flat(_day(2027, 2, 7), _openKg)),
      );
      await setup.reviewer.reviewDueWeek();

      await setup.reviewer.reviewDueWeek();

      final goal = (await setup.store.active())!;
      expect(goal.phase, GoalPhase.maintenance);
      expect(goal.phaseSince, _day(2027, 2, 8));
      expect(goal.phaseUntil, _day(2027, 3, 7));
      expect(await setup.weeks(), hasLength(1));
    });

    test('Body off closes by the date alone', () async {
      final setup = await _reviewing(
        now: _at(2027, 2, 8),
        weight: _throwingWeight(),
        modules: const {ModuleId.goals},
      );

      await setup.reviewer.reviewDueWeek();

      expect((await setup.store.active())!.phase, GoalPhase.maintenance);
    });

    test('no weight summary closes by the date alone', () async {
      final setup = await _reviewing(now: _at(2027, 2, 8), weight: _noWeight());

      await setup.reviewer.reviewDueWeek();

      expect((await setup.store.active())!.phase, GoalPhase.maintenance);
    });

    test('no weight summary before the end leaves the block running', () async {
      final setup = await _reviewing(
        now: _at(2027, 1, 18),
        weight: _noWeight(),
      );

      await setup.reviewer.reviewDueWeek();

      expect((await setup.store.active())!.phase, GoalPhase.block);
    });

    test('the app closed for five weeks maintains from the Monday it '
        'opens', () async {
      final setup = await _reviewing(
        now: _at(2027, 3, 22),
        weight: _weightOf(_flat(_day(2027, 3, 21), _openKg)),
      );

      await setup.reviewer.reviewDueWeek();

      final goal = (await setup.store.active())!;
      expect(goal.phase, GoalPhase.maintenance);
      expect(goal.phaseSince, _day(2027, 3, 22));
      expect(goal.phaseUntil, _day(2027, 4, 18));
    });
  });

  group('G11b1 criterion 2: the trend closes the block in week 9', () {
    final week9 = _at(2027, 1, 18);

    test(
      'a Sunday trend 10 percent under the anchor closes at the Monday',
      () async {
        final setup = await _reviewing(
          now: week9,
          weight: _weightOf(_flat(_day(2027, 1, 17), _closedKg)),
        );

        await setup.reviewer.reviewDueWeek();

        final goal = (await setup.store.active())!;
        expect(goal.phase, GoalPhase.maintenance);
        expect(goal.phaseSince, _day(2027, 1, 18));
        expect(goal.phaseUntil, _day(2027, 2, 14));
      },
    );

    test('a Sunday trend above that line leaves the block running', () async {
      final setup = await _reviewing(
        now: week9,
        weight: _weightOf(_flat(_day(2027, 1, 17), _openKg)),
      );

      await setup.reviewer.reviewDueWeek();

      expect((await setup.store.active())!.phase, GoalPhase.block);
    });

    test(
      'a block that reaches the line midweek waits for the Monday',
      () async {
        final days = [
          ..._flat(_day(2027, 1, 17), _anchorKg),
          for (var d = 18; d <= 20; d++) (date: _day(2027, 1, d), value: 70.0),
        ];
        final setup = await _reviewing(
          now: _at(2027, 1, 20),
          weight: _weightOf(days),
        );

        await setup.reviewer.reviewDueWeek();

        expect((await setup.store.active())!.phase, GoalPhase.block);
      },
    );
  });

  group('G11b1 criterion 3: a maintenance week answers with no change', () {
    final monday = _at(2027, 2, 15);

    Future<GoalSetup> keeping() => _maintaining(
      now: monday,
      since: _day(2027, 2, 8),
      weight: _weightOf(_flat(_day(2027, 2, 14), _closedKg)),
    );

    test('the review is a hold with no change', () async {
      final setup = await keeping();

      final review = await setup.reviewer.reviewDueWeek();

      expect(review, isNotNull);
      expect(review!.action, ReviewAction.hold);
      expect(review.change, isNull);
    });

    test(
      'the stored row holds, has no change and is a maintenance row',
      () async {
        final setup = await keeping();

        await setup.reviewer.reviewDueWeek();

        final row = (await setup.weeks()).single;
        expect(row.action, ReviewAction.hold);
        expect(row.change, isNull);
        expect(row.inputs.maintenance, isTrue);
      },
    );

    test('the Monday does not close the block again', () async {
      final setup = await keeping();

      await setup.reviewer.reviewDueWeek();

      final goal = (await setup.store.active())!;
      expect(goal.phase, GoalPhase.maintenance);
      expect(goal.phaseSince, _day(2027, 2, 8));
      expect(goal.phaseUntil, _day(2027, 3, 7));
    });

    test('rule 1 still ends the goal in maintenance', () async {
      final setup = await keeping();
      await setup.store.addScreening(
        const GoalScreening(
          on: LocalDate(2027, 2, 9),
          softMode: null,
          pregnantOrBreastfeeding: true,
        ),
      );

      final review = await setup.reviewer.reviewDueWeek();

      expect(review!.rule, ReviewRule.end);
      expect((await setup.store.goals()).single.phase, GoalPhase.ended);
    });
  });

  group('G11b1 criterion 4: a check-in amend on a maintenance row', () {
    Future<GoalSetup> keepingWithRow() async {
      final setup = await _maintaining(
        now: _at(2026, 12, 7),
        since: _day(2026, 12, 7),
      );
      await _addRow(setup, _day(2026, 12, 7), _inputs(f1, energy: null));
      return setup;
    }

    test('the row of the fixture holds before the amend', () async {
      final setup = await keepingWithRow();

      final row = (await setup.weeks()).single;

      expect(row.action, ReviewAction.hold);
      expect(row.change, isNull);
    });

    test('recomputes to no proposal', () async {
      final setup = await keepingWithRow();

      final review = await setup.reviewer.checkIn(
        _day(2026, 12, 7),
        energy: CheckInEnergy.good,
      );

      expect(review, isNotNull);
      expect(review!.action, ReviewAction.hold);
      expect(review.change, isNull);
    });

    test('the amended row stays a maintenance row with no change', () async {
      final setup = await keepingWithRow();

      await setup.reviewer.checkIn(
        _day(2026, 12, 7),
        energy: CheckInEnergy.good,
      );

      final row = (await setup.weeks()).single;
      expect(row.inputs.maintenance, isTrue);
      expect(row.inputs.energy, CheckInEnergy.good);
      expect(row.change, isNull);
    });

    test('the goal stays in maintenance', () async {
      final setup = await keepingWithRow();

      await setup.reviewer.checkIn(
        _day(2026, 12, 7),
        energy: CheckInEnergy.good,
      );

      expect((await setup.store.active())!.phase, GoalPhase.maintenance);
    });
  });

  group('G11b1 criterion 5: the next block follows maintenance', () {
    Future<GoalSetup> over(DateTime now) => _maintaining(
      now: now,
      since: _day(2027, 2, 8),
      weight: _weightOf(_flat(_day(2027, 3, 7), _closedKg)),
    );

    test('the day after maintenance ends starts the block', () async {
      final setup = await over(_at(2027, 3, 8));

      expect(await setup.reviewer.startDueBlock(), isTrue);

      final goal = (await setup.store.active())!;
      expect(goal.phase, GoalPhase.block);
      expect(goal.blockStartedOn, _day(2027, 3, 8));
      expect(goal.phaseSince, _day(2027, 3, 8));
      expect(goal.phaseUntil, isNull);
    });

    test('anchors the block on the ready trend of the day', () async {
      final setup = await over(_at(2027, 3, 8));
      final trend = weightSnapshot(
        daily: _flat(_day(2027, 3, 7), _closedKg),
        asOf: _day(2027, 3, 8),
      ).trendKg;

      await setup.reviewer.startDueBlock();

      expect(trend, isNotNull);
      expect((await setup.store.active())!.blockAnchorKg, trend);
    });

    test('keeps the levers of the goal', () async {
      final setup = await over(_at(2027, 3, 8));

      await setup.reviewer.startDueBlock();

      expectSameLevers((await setup.store.active())!.levers, const [
        strengthLever,
        sleepLever,
        stepsLever,
      ]);
    });

    test('the last day of maintenance starts nothing', () async {
      final setup = await _maintaining(
        now: _at(2027, 3, 7),
        since: _day(2027, 2, 8),
        weight: _weightOf(_flat(_day(2027, 3, 6), _closedKg)),
      );

      expect(await setup.reviewer.startDueBlock(), isFalse);
      expect((await setup.store.active())!.phase, GoalPhase.maintenance);
    });

    test('a day inside maintenance starts nothing', () async {
      final setup = await _maintaining(
        now: _at(2027, 2, 20),
        since: _day(2027, 2, 8),
        weight: _weightOf(_flat(_day(2027, 2, 19), _closedKg)),
      );

      expect(await setup.reviewer.startDueBlock(), isFalse);
      expect((await setup.store.active())!.phase, GoalPhase.maintenance);
    });

    test('without a ready trend the block waits', () async {
      final setup = await _maintaining(
        now: _at(2027, 3, 8),
        since: _day(2027, 2, 8),
        weight: _noWeight(),
      );

      expect(await setup.reviewer.startDueBlock(), isFalse);
      expect((await setup.store.active())!.phase, GoalPhase.maintenance);
    });
  });

  group('G11b1 criterion 6: other kinds have no maintenance', () {
    test('lose fat on the same Monday does enter it', () async {
      final setup = await _reviewing(now: _at(2027, 2, 8), weight: _noWeight());

      await setup.reviewer.reviewDueWeek();

      expect((await setup.store.active())!.phase, GoalPhase.maintenance);
    });

    for (final kind in [GoalKind.getFitter, GoalKind.sleepBetter]) {
      test('${kind.name} stays in its block past 12 weeks', () async {
        final control = await _reviewing(
          now: _at(2027, 2, 8),
          weight: _noWeight(),
        );
        await control.reviewer.reviewDueWeek();
        final setup = await _reviewing(
          now: _at(2027, 2, 8),
          weight: _throwingWeight(),
          kind: kind,
        );

        await setup.reviewer.reviewDueWeek();

        expect((await control.store.active())!.phase, GoalPhase.maintenance);
        final goal = (await setup.store.active())!;
        expect(goal.phase, GoalPhase.block);
        expect(goal.phaseUntil, isNull);
        expect((await setup.weeks()).single.inputs.maintenance, isFalse);
      });
    }
  });

  group('G11b1 decision D4: a pause during maintenance', () {
    test('a check-in twice pauses the goal from that Monday', () async {
      final setup = await _maintaining(
        now: _at(2026, 12, 7),
        since: _day(2026, 11, 30),
      );
      final previous = _inputs(
        f1,
        energy: CheckInEnergy.low,
        energyPrevious: CheckInEnergy.normal,
      );
      final current = _inputs(f1, energyPrevious: CheckInEnergy.low);
      await _addRow(setup, _day(2026, 11, 30), previous);
      await _addRow(setup, _day(2026, 12, 7), current);

      await setup.reviewer.checkIn(
        _day(2026, 12, 7),
        energy: CheckInEnergy.low,
      );

      final goal = (await setup.store.active())!;
      expect(goal.phase, GoalPhase.paused);
      expect(goal.phaseSince, _day(2026, 12, 7));
    });
  });
}
