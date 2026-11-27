import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_codec.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/goals/infrastructure/drift_goal_store.dart';

import '../../../helpers/database.dart';
import '../goal_draft_fixture.dart';
import '../goal_fixtures.dart';

const _start = LocalDate(2026, 11, 16);
const _firstMonday = LocalDate(2026, 12, 7);
const _secondMonday = LocalDate(2026, 12, 14);
const _tuesday = LocalDate(2026, 12, 8);
const _pauseEnd = LocalDate(2027, 1, 3);
const _nextBlock = LocalDate(2027, 3, 8);
const _endDay = LocalDate(2026, 12, 10);

const _holdReview = Review(
  rule: ReviewRule.holdOther,
  action: ReviewAction.hold,
  adherence: 1,
);

const _noLeversDraft = GoalDraft(
  kind: GoalKind.loseFat,
  pace: GoalPace.standard,
  startedOn: _start,
  anchorKg: 78.4,
  referenceKg: 74,
  levers: [],
);

void expectPaused(Goal? goal, {required LocalDate since, LocalDate? until}) {
  expect(goal, isNotNull);
  expect(goal!.phase, GoalPhase.paused);
  expect(goal.phaseSince, since);
  expect(goal.phaseUntil, until);
}

void main() {
  final stores = <String, GoalStore Function()>{
    'InMemoryGoalStore': InMemoryGoalStore.new,
    'DriftGoalStore': () => DriftGoalStore(memoryDatabase()),
  };

  for (final MapEntry(key: name, value: create) in stores.entries) {
    group('goal store contract on $name', () {
      late GoalStore store;
      late Review f1Review;

      setUp(() {
        store = create();
        f1Review = reviewWeek(f1);
      });

      Future<void> startWithWeek() async {
        await store.start(draftD);
        await store.addWeek(
          1,
          monday: _firstMonday,
          inputs: f1,
          review: f1Review,
        );
      }

      group('criterion 8: a fresh store', () {
        test('has no active goal', () async {
          expect(await store.active(), isNull);
        });

        test('counts 0 rows', () async {
          expect(await store.count(), 0);
        });

        test('clears 0 rows', () async {
          expect(await store.clear(), 0);
        });

        test('lists no goals and no screenings', () async {
          expect(await store.goals(), isEmpty);
          expect(await store.screenings(), isEmpty);
        });
      });

      group('criterion 9: start', () {
        test(
          'returns goal 1 in phase block with the block set to the start',
          () async {
            final goal = await store.start(draftD);

            expect(goal, isNotNull);
            expect(goal!.id, 1);
            expect(goal.kind, GoalKind.loseFat);
            expect(goal.pace, GoalPace.standard);
            expect(goal.startedOn, _start);
            expect(goal.anchorKg, 78.4);
            expect(goal.referenceKg, 74.0);
            expect(goal.phase, GoalPhase.block);
            expect(goal.phaseSince, _start);
            expect(goal.phaseUntil, isNull);
            expect(goal.blockStartedOn, _start);
            expect(goal.blockAnchorKg, 78.4);
            expect(goal.endedOn, isNull);
            expect(goal.endReason, isNull);
            expect(goal.active, isTrue);
            expectSameLevers(goal.levers, const [strengthLever]);
          },
        );

        test('makes active return the same goal', () async {
          final started = await store.start(draftD);

          expectSameGoal(await store.active(), started!);
        });

        test('keeps a null pace, anchor and reference as null', () async {
          const draft = GoalDraft(
            kind: GoalKind.sleepBetter,
            pace: null,
            startedOn: _start,
            anchorKg: null,
            referenceKg: null,
            levers: [],
          );

          final goal = await store.start(draft);

          expect(goal, isNotNull);
          expect(goal!.pace, isNull);
          expect(goal.anchorKg, isNull);
          expect(goal.referenceKg, isNull);
          expect(goal.blockAnchorKg, isNull);
          expect(goal.levers, isEmpty);
        });
      });

      group('criterion 10: a second start', () {
        test('returns null while a goal is active', () async {
          await store.start(draftD);

          expect(await store.start(draftD), isNull);
        });

        test('leaves one goal in the list', () async {
          await store.start(draftD);
          await store.start(draftD);

          expect(await store.goals(), hasLength(1));
        });
      });

      group('criterion 11: addWeek', () {
        test('is true once and false for the same Monday', () async {
          await store.start(draftD);

          final first = await store.addWeek(
            1,
            monday: _firstMonday,
            inputs: f1,
            review: f1Review,
          );
          final second = await store.addWeek(
            1,
            monday: _firstMonday,
            inputs: f1,
            review: f1Review,
          );

          expect(first, isTrue);
          expect(second, isFalse);
        });

        test(
          'stores one row with the rule, a pending change and the inputs',
          () async {
            await startWithWeek();

            final weeks = await store.weeks(1);

            expect(weeks, hasLength(1));
            final week = weeks.single;
            expect(week.goalId, 1);
            expect(week.monday, _firstMonday);
            expect(week.rule, ReviewRule.build);
            expect(week.action, ReviewAction.nextStep);
            expect(week.pending, isTrue);
            expect(week.answer, isNull);
            expectSameChange(
              week.change,
              const LeverChange(kind: LeverKind.steps, from: 9000, to: 10000),
            );
            expect(encodeReviewInputs(week.inputs), encodeReviewInputs(f1));
          },
        );

        test('stores a review with no change as not pending', () async {
          await store.start(draftD);
          await store.addWeek(
            1,
            monday: _firstMonday,
            inputs: f1,
            review: _holdReview,
          );

          final week = (await store.weeks(1)).single;

          expect(week.rule, ReviewRule.holdOther);
          expect(week.action, ReviewAction.hold);
          expect(week.change, isNull);
          expect(week.pending, isFalse);
        });

        test('lists the weeks by Monday ascending', () async {
          await store.start(draftD);
          await store.addWeek(
            1,
            monday: _secondMonday,
            inputs: f1,
            review: f1Review,
          );
          await store.addWeek(
            1,
            monday: _firstMonday,
            inputs: f1,
            review: f1Review,
          );

          final weeks = await store.weeks(1);

          expect(
            [for (final week in weeks) week.monday],
            [_firstMonday, _secondMonday],
          );
        });

        test('lists no weeks for a goal that has none', () async {
          await store.start(draftD);

          expect(await store.weeks(1), isEmpty);
        });
      });

      group('criterion 12: addWeek refusals', () {
        test('inputs with a number that is not finite throw and store '
            'nothing', () async {
          await store.start(draftD);

          await expectLater(
            store.addWeek(
              1,
              monday: _firstMonday,
              inputs: f1WithBmi(double.infinity),
              review: f1Review,
            ),
            throwsArgumentError,
          );

          expect(await store.weeks(1), isEmpty);
        });

        test('inputs that are not finite throw for an unknown goal '
            'too', () async {
          await expectLater(
            store.addWeek(
              99,
              monday: _firstMonday,
              inputs: f1WithBmi(double.nan),
              review: f1Review,
            ),
            throwsArgumentError,
          );
        });

        test(
          'a day that is not a Monday is false and stores nothing',
          () async {
            await store.start(draftD);

            final added = await store.addWeek(
              1,
              monday: _tuesday,
              inputs: f1,
              review: f1Review,
            );

            expect(added, isFalse);
            expect(await store.weeks(1), isEmpty);
          },
        );

        test('an unknown goal is false', () async {
          await store.start(draftD);

          final added = await store.addWeek(
            99,
            monday: _firstMonday,
            inputs: f1,
            review: f1Review,
          );

          expect(added, isFalse);
          expect(await store.count(), 1);
        });
      });

      group('criterion 13: answer accepted', () {
        test('is true and appends the change to the levers', () async {
          await startWithWeek();

          final answered = await store.answer(
            1,
            _firstMonday,
            WeekAnswer.accepted,
          );

          expect(answered, isTrue);
          final goal = await store.active();
          expectSameLevers(goal!.levers, const [
            strengthLever,
            Lever(kind: LeverKind.steps, target: 10000),
          ]);
        });

        test('records the answer on the week', () async {
          await startWithWeek();

          await store.answer(1, _firstMonday, WeekAnswer.accepted);

          final week = (await store.weeks(1)).single;
          expect(week.answer, WeekAnswer.accepted);
          expect(week.pending, isFalse);
        });

        test('a second answer is false and keeps the first', () async {
          await startWithWeek();
          await store.answer(1, _firstMonday, WeekAnswer.accepted);

          final again = await store.answer(
            1,
            _firstMonday,
            WeekAnswer.declined,
          );

          expect(again, isFalse);
          final week = (await store.weeks(1)).single;
          expect(week.answer, WeekAnswer.accepted);
          expectSameLevers((await store.active())!.levers, const [
            strengthLever,
            Lever(kind: LeverKind.steps, target: 10000),
          ]);
        });
      });

      group('criterion 14: answer declined', () {
        test('is true and leaves the levers unchanged', () async {
          await startWithWeek();

          final answered = await store.answer(
            1,
            _firstMonday,
            WeekAnswer.declined,
          );

          expect(answered, isTrue);
          expectSameLevers((await store.active())!.levers, const [
            strengthLever,
          ]);
        });

        test('reads declined on the week', () async {
          await startWithWeek();

          await store.answer(1, _firstMonday, WeekAnswer.declined);

          final week = (await store.weeks(1)).single;
          expect(week.answer, WeekAnswer.declined);
          expect(week.pending, isFalse);
        });
      });

      group('answer refusals', () {
        test('a week with no change cannot be answered', () async {
          await store.start(draftD);
          await store.addWeek(
            1,
            monday: _firstMonday,
            inputs: f1,
            review: _holdReview,
          );

          final answered = await store.answer(
            1,
            _firstMonday,
            WeekAnswer.accepted,
          );

          expect(answered, isFalse);
          expect((await store.weeks(1)).single.answer, isNull);
          expectSameLevers((await store.active())!.levers, const [
            strengthLever,
          ]);
        });

        test('an unknown Monday is false', () async {
          await startWithWeek();

          final answered = await store.answer(
            1,
            _secondMonday,
            WeekAnswer.accepted,
          );

          expect(answered, isFalse);
        });

        test('an unknown goal is false', () async {
          await startWithWeek();

          final answered = await store.answer(
            99,
            _firstMonday,
            WeekAnswer.accepted,
          );

          expect(answered, isFalse);
        });

        test('an ended goal is false and its levers do not change', () async {
          await startWithWeek();
          await store.end(1, on: _endDay, reason: GoalEndReason.person);

          final answered = await store.answer(
            1,
            _firstMonday,
            WeekAnswer.accepted,
          );

          final goal = (await store.goals()).single;
          expect(answered, isFalse);
          expect((await store.weeks(1)).single.answer, isNull);
          expectSameLevers(goal.levers, const [strengthLever]);
        });
      });

      group('criterion 15: setPhase', () {
        test('stores a pause with its dates', () async {
          await store.start(draftD);

          final changed = await store.setPhase(
            1,
            GoalPhase.paused,
            since: _firstMonday,
            until: _pauseEnd,
          );

          expect(changed, isTrue);
          final goal = (await store.active())!;
          expect(goal.phase, GoalPhase.paused);
          expect(goal.phaseSince, _firstMonday);
          expect(goal.phaseUntil, _pauseEnd);
          expect(goal.active, isTrue);
        });

        test('stores a phase without an until as null', () async {
          await store.start(draftD);

          await store.setPhase(1, GoalPhase.maintenance, since: _firstMonday);

          final goal = (await store.active())!;
          expect(goal.phase, GoalPhase.maintenance);
          expect(goal.phaseUntil, isNull);
        });

        test('ended is false and leaves the phase as it was', () async {
          await store.start(draftD);

          final changed = await store.setPhase(
            1,
            GoalPhase.ended,
            since: _firstMonday,
          );

          expect(changed, isFalse);
          expect((await store.active())!.phase, GoalPhase.block);
        });

        test('an unknown goal is false', () async {
          await store.start(draftD);

          final changed = await store.setPhase(
            99,
            GoalPhase.paused,
            since: _firstMonday,
          );

          expect(changed, isFalse);
        });

        test('an ended goal is false', () async {
          await store.start(draftD);
          await store.end(1, on: _endDay, reason: GoalEndReason.person);

          final changed = await store.setPhase(
            1,
            GoalPhase.paused,
            since: _firstMonday,
          );

          expect(changed, isFalse);
          expect((await store.goals()).single.phase, GoalPhase.ended);
        });
      });

      group('criterion 16: startBlock', () {
        test(
          'keeps the goal start and anchor and clears the pause end',
          () async {
            await store.start(draftD);
            await store.setPhase(
              1,
              GoalPhase.paused,
              since: _firstMonday,
              until: _pauseEnd,
            );

            final changed = await store.startBlock(
              1,
              on: _nextBlock,
              anchorKg: 74.9,
            );

            expect(changed, isTrue);
            final goal = (await store.active())!;
            expect(goal.startedOn, _start);
            expect(goal.anchorKg, 78.4);
            expect(goal.blockStartedOn, _nextBlock);
            expect(goal.blockAnchorKg, 74.9);
            expect(goal.phase, GoalPhase.block);
            expect(goal.phaseUntil, isNull);
          },
        );

        test('stores a null anchor as null', () async {
          await store.start(draftD);

          await store.startBlock(1, on: _nextBlock, anchorKg: null);

          final goal = (await store.active())!;
          expect(goal.blockStartedOn, _nextBlock);
          expect(goal.blockAnchorKg, isNull);
        });
      });

      group('criterion 17: end', () {
        test('removes the active goal and keeps its weeks', () async {
          await startWithWeek();

          final ended = await store.end(
            1,
            on: _endDay,
            reason: GoalEndReason.person,
          );

          expect(ended, isTrue);
          expect(await store.active(), isNull);
          expect(await store.weeks(1), hasLength(1));
        });

        test('records the phase, the day and the reason', () async {
          await store.start(draftD);

          await store.end(1, on: _endDay, reason: GoalEndReason.protection);

          final goal = (await store.goals()).single;
          expect(goal.phase, GoalPhase.ended);
          expect(goal.endedOn, _endDay);
          expect(goal.endReason, GoalEndReason.protection);
          expect(goal.active, isFalse);
        });

        test('a second end is false and keeps the first reason', () async {
          await store.start(draftD);
          await store.end(1, on: _endDay, reason: GoalEndReason.person);

          final again = await store.end(
            1,
            on: _nextBlock,
            reason: GoalEndReason.switched,
          );

          final goal = (await store.goals()).single;
          expect(again, isFalse);
          expect(goal.endedOn, _endDay);
          expect(goal.endReason, GoalEndReason.person);
        });

        test('addWeek on the ended goal is false', () async {
          await startWithWeek();
          await store.end(1, on: _endDay, reason: GoalEndReason.person);

          final added = await store.addWeek(
            1,
            monday: _secondMonday,
            inputs: f1,
            review: f1Review,
          );

          expect(added, isFalse);
          expect(await store.weeks(1), hasLength(1));
        });

        test('start works again and returns id 2', () async {
          await store.start(draftD);
          await store.end(1, on: _endDay, reason: GoalEndReason.person);

          final next = await store.start(draftD);

          expect(next, isNotNull);
          expect(next!.id, 2);
          expect((await store.active())!.id, 2);
        });

        test('goals lists the newest id first', () async {
          await store.start(draftD);
          await store.end(1, on: _endDay, reason: GoalEndReason.person);
          await store.start(draftD);

          final goals = await store.goals();

          expect([for (final goal in goals) goal.id], [2, 1]);
        });
      });

      group('criterion 18: screenings', () {
        test('come back newest first', () async {
          await store.addScreening(
            const GoalScreening(
              on: _start,
              softMode: false,
              pregnantOrBreastfeeding: null,
            ),
          );
          await store.addScreening(
            const GoalScreening(
              on: _nextBlock,
              softMode: null,
              pregnantOrBreastfeeding: false,
            ),
          );

          final screenings = await store.screenings();

          expect(screenings, hasLength(2));
          expect(screenings[0].on, _nextBlock);
          expect(screenings[0].softMode, isNull);
          expect(screenings[0].pregnantOrBreastfeeding, isFalse);
          expect(screenings[1].on, _start);
          expect(screenings[1].softMode, isFalse);
          expect(screenings[1].pregnantOrBreastfeeding, isNull);
        });

        test('on the same day come back with the later id first', () async {
          await store.addScreening(
            const GoalScreening(
              on: _start,
              softMode: true,
              pregnantOrBreastfeeding: null,
            ),
          );
          await store.addScreening(
            const GoalScreening(
              on: _start,
              softMode: false,
              pregnantOrBreastfeeding: null,
            ),
          );

          final screenings = await store.screenings();

          expect([for (final one in screenings) one.softMode], [false, true]);
        });

        test('need no goal', () async {
          await store.addScreening(
            const GoalScreening(
              on: _start,
              softMode: true,
              pregnantOrBreastfeeding: true,
            ),
          );

          expect(await store.active(), isNull);
          expect(await store.count(), 1);
        });
      });

      group('criterion 19: count and clear', () {
        Future<void> fill() async {
          await startWithWeek();
          await store.addScreening(
            const GoalScreening(
              on: _start,
              softMode: false,
              pregnantOrBreastfeeding: null,
            ),
          );
          await store.addScreening(
            const GoalScreening(
              on: _nextBlock,
              softMode: null,
              pregnantOrBreastfeeding: false,
            ),
          );
        }

        test('count adds the rows of the three tables', () async {
          await fill();

          expect(await store.count(), 4);
        });

        test('clear returns that count', () async {
          await fill();

          expect(await store.clear(), 4);
        });

        test('count is 0 after a clear and every read is empty', () async {
          await fill();
          await store.clear();

          expect(await store.count(), 0);
          expect(await store.active(), isNull);
          expect(await store.goals(), isEmpty);
          expect(await store.weeks(1), isEmpty);
          expect(await store.screenings(), isEmpty);
        });

        test('clear twice returns 0 the second time', () async {
          await fill();
          await store.clear();

          expect(await store.clear(), 0);
        });

        test('a goal can be started after a clear', () async {
          await fill();
          await store.clear();

          final goal = await store.start(draftD);

          expect(goal, isNotNull);
          expect(await store.count(), 1);
        });
      });

      group('G5b2a amendWeek', () {
        const lastMonday = LocalDate(2026, 11, 30);

        Future<void> addRow(LocalDate monday, ReviewInputs inputs) =>
            store.addWeek(
              1,
              monday: monday,
              inputs: inputs,
              review: reviewWeek(inputs),
            );

        Future<void> startWithPausableWeeks() async {
          await store.start(draftD);
          await addRow(
            lastMonday,
            f1With(
              energy: CheckInEnergy.low,
              energyPrevious: CheckInEnergy.normal,
              foodOrWeight: false,
            ),
          );
          await addRow(
            _firstMonday,
            f1With(
              energy: null,
              energyPrevious: CheckInEnergy.low,
              foodOrWeight: null,
            ),
          );
        }

        Future<void> startWithBuildWeek() async {
          await store.start(draftD);
          await addRow(
            _firstMonday,
            f1With(
              energy: null,
              energyPrevious: CheckInEnergy.normal,
              foodOrWeight: null,
            ),
          );
        }

        Future<void> expectUntouched(
          Future<Review?> Function() amend,
          GoalWeek before,
        ) async {
          expect(await amend(), isNull);

          final after = (await store.weeks(1)).last;
          expect(after.monday, before.monday);
          expect(after.rule, before.rule);
          expect(after.action, before.action);
          expectSameChange(after.change, before.change);
          expect(after.answer, before.answer);
          expect(
            encodeReviewInputs(after.inputs),
            encodeReviewInputs(before.inputs),
          );
        }

        test('case 4: a second low energy gives the check-in pause', () async {
          await startWithPausableWeeks();

          final review = await store.amendWeek(
            1,
            _firstMonday,
            energy: CheckInEnergy.low,
            foodOrWeight: null,
          );

          expect(review, isNotNull);
          expect(review!.rule, ReviewRule.pauseCheckIn);
          expect(review.action, ReviewAction.pause);
          expect(review.pauseDays, isNull);
        });

        test('case 4: the row then holds the rule, no change and the '
            'energy', () async {
          await startWithPausableWeeks();

          await store.amendWeek(
            1,
            _firstMonday,
            energy: CheckInEnergy.low,
            foodOrWeight: null,
          );

          final week = (await store.weeks(1)).last;
          expect(week.monday, _firstMonday);
          expect(week.rule, ReviewRule.pauseCheckIn);
          expect(week.action, ReviewAction.pause);
          expect(week.change, isNull);
          expect(week.pending, isFalse);
          expect(week.inputs.energy, CheckInEnergy.low);
          expect(week.inputs.foodOrWeight, isNull);
        });

        test('case 5: a second amend of the week is refused and '
            'changes nothing', () async {
          await startWithPausableWeeks();
          await store.amendWeek(
            1,
            _firstMonday,
            energy: CheckInEnergy.low,
            foodOrWeight: null,
          );
          final before = (await store.weeks(1)).last;

          await expectUntouched(
            () => store.amendWeek(
              1,
              _firstMonday,
              energy: CheckInEnergy.good,
              foodOrWeight: true,
            ),
            before,
          );
        });

        Future<void> startWithTwoOpenWeeks() async {
          await store.start(draftD);
          for (final monday in [lastMonday, _firstMonday]) {
            await addRow(
              monday,
              f1With(
                energy: null,
                energyPrevious: CheckInEnergy.normal,
                foodOrWeight: null,
              ),
            );
          }
        }

        test('an older week with no check-in is refused', () async {
          await startWithTwoOpenWeeks();
          final older = (await store.weeks(1)).first;

          final review = await store.amendWeek(
            1,
            lastMonday,
            energy: CheckInEnergy.low,
            foodOrWeight: null,
          );

          expect(review, isNull);
          final after = (await store.weeks(1)).first;
          expect(after.inputs.energy, isNull);
          expect(
            encodeReviewInputs(after.inputs),
            encodeReviewInputs(older.inputs),
          );
        });

        test('an older pending week can no longer be answered', () async {
          await startWithTwoOpenWeeks();
          final before = (await store.active())!.levers;

          final answered = await store.answer(
            1,
            lastMonday,
            WeekAnswer.accepted,
          );

          final weeks = await store.weeks(1);
          expect(weeks.first.pending, isTrue);
          expect(answered, isFalse);
          expect(weeks.first.answer, isNull);
          expect(
            encodeLevers((await store.active())!.levers),
            encodeLevers(before),
          );
        });

        test('the newest of two pending weeks is answered', () async {
          await startWithTwoOpenWeeks();

          final answered = await store.answer(
            1,
            _firstMonday,
            WeekAnswer.accepted,
          );

          expect(answered, isTrue);
          expect((await store.weeks(1)).last.answer, WeekAnswer.accepted);
        });

        test('case 6: a week that is not the newest is refused', () async {
          await startWithPausableWeeks();
          final older = (await store.weeks(1)).first;

          final review = await store.amendWeek(
            1,
            lastMonday,
            energy: CheckInEnergy.low,
            foodOrWeight: null,
          );

          expect(review, isNull);
          final after = (await store.weeks(1)).first;
          expect(after.rule, older.rule);
          expect(
            encodeReviewInputs(after.inputs),
            encodeReviewInputs(older.inputs),
          );
        });

        test('case 6: no answer at all is refused and a later amend '
            'still works', () async {
          await startWithPausableWeeks();
          final before = (await store.weeks(1)).last;

          await expectUntouched(
            () => store.amendWeek(
              1,
              _firstMonday,
              energy: null,
              foodOrWeight: null,
            ),
            before,
          );

          final later = await store.amendWeek(
            1,
            _firstMonday,
            energy: CheckInEnergy.low,
            foodOrWeight: null,
          );
          expect(later?.rule, ReviewRule.pauseCheckIn);
        });

        test('case 6: an answered week is refused', () async {
          await startWithPausableWeeks();
          await store.answer(1, _firstMonday, WeekAnswer.declined);
          final before = (await store.weeks(1)).last;

          await expectUntouched(
            () => store.amendWeek(
              1,
              _firstMonday,
              energy: CheckInEnergy.low,
              foodOrWeight: null,
            ),
            before,
          );
        });

        test('case 6: a week with a stored check-in answer is '
            'refused', () async {
          await store.start(draftD);
          await addRow(
            _firstMonday,
            f1With(
              energy: null,
              energyPrevious: CheckInEnergy.low,
              foodOrWeight: false,
            ),
          );
          final before = (await store.weeks(1)).last;

          await expectUntouched(
            () => store.amendWeek(
              1,
              _firstMonday,
              energy: CheckInEnergy.low,
              foodOrWeight: null,
            ),
            before,
          );
        });

        test('case 6: an ended goal is refused', () async {
          await startWithPausableWeeks();
          await store.end(1, on: _endDay, reason: GoalEndReason.person);
          final before = (await store.weeks(1)).last;

          await expectUntouched(
            () => store.amendWeek(
              1,
              _firstMonday,
              energy: CheckInEnergy.low,
              foodOrWeight: null,
            ),
            before,
          );
        });

        test('case 6: an unknown Monday is refused', () async {
          await startWithPausableWeeks();
          final before = (await store.weeks(1)).last;

          await expectUntouched(
            () => store.amendWeek(
              1,
              _secondMonday,
              energy: CheckInEnergy.low,
              foodOrWeight: null,
            ),
            before,
          );
          expect(await store.weeks(1), hasLength(2));
        });

        test(
          'case 7: a pending build week keeps its rule and change',
          () async {
            await startWithBuildWeek();

            final review = await store.amendWeek(
              1,
              _firstMonday,
              energy: CheckInEnergy.normal,
              foodOrWeight: null,
            );

            expect(review?.rule, ReviewRule.build);
            final week = (await store.weeks(1)).single;
            expect(week.rule, ReviewRule.build);
            expect(week.action, ReviewAction.nextStep);
            expectSameChange(
              week.change,
              const LeverChange(kind: LeverKind.steps, from: 9000, to: 10000),
            );
            expect(week.pending, isTrue);
            expect(week.answer, isNull);
            expect(week.inputs.energy, CheckInEnergy.normal);
          },
        );

        group('G5b2b1 case 1: startBlock with levers', () {
          const blockDay = LocalDate(2026, 11, 26);

          test('starts the block on the day with the anchor', () async {
            await store.start(_noLeversDraft);

            final changed = await store.startBlock(
              1,
              on: blockDay,
              anchorKg: 77.9,
              levers: const [strengthLever],
            );

            final goal = (await store.active())!;
            expect(changed, isTrue);
            expect(goal.phase, GoalPhase.block);
            expect(goal.blockStartedOn, blockDay);
            expect(goal.phaseSince, blockDay);
            expect(goal.phaseUntil, isNull);
            expect(goal.blockAnchorKg, 77.9);
          });

          test('stores the levers it is given on a goal with none', () async {
            await store.start(_noLeversDraft);

            await store.startBlock(
              1,
              on: blockDay,
              anchorKg: 77.9,
              levers: const [strengthLever],
            );

            expectSameLevers((await store.active())!.levers, const [
              strengthLever,
            ]);
          });

          test('keeps the start and the anchor of the goal', () async {
            await store.start(_noLeversDraft);

            await store.startBlock(
              1,
              on: blockDay,
              anchorKg: 77.9,
              levers: const [strengthLever],
            );

            final goal = (await store.active())!;
            expect(goal.startedOn, _start);
            expect(goal.anchorKg, 78.4);
          });

          test('replaces the levers it is given over stored ones', () async {
            await store.start(draftD);

            await store.startBlock(
              1,
              on: blockDay,
              anchorKg: 77.9,
              levers: const [stepsLever],
            );

            expectSameLevers((await store.active())!.levers, const [
              stepsLever,
            ]);
          });

          test('null levers keep the stored ones', () async {
            await store.start(draftD);

            await store.startBlock(1, on: blockDay, anchorKg: 77.9);

            expectSameLevers((await store.active())!.levers, const [
              strengthLever,
            ]);
          });

          test('an ended goal is refused and its levers stay', () async {
            await store.start(draftD);
            await store.end(1, on: _endDay, reason: GoalEndReason.person);

            final changed = await store.startBlock(
              1,
              on: blockDay,
              anchorKg: 77.9,
              levers: const [stepsLever],
            );

            final goal = (await store.goals()).single;
            expect(changed, isFalse);
            expectSameLevers(goal.levers, const [strengthLever]);
            expect(goal.phase, GoalPhase.ended);
          });
        });

        group('G5b2b1 cases 2 to 5: addWeek applies a protection', () {
          final checkInPause = f1With(
            energy: CheckInEnergy.low,
            energyPrevious: CheckInEnergy.low,
            foodOrWeight: null,
          );

          test(
            'case 2: rule 3 pauses the goal from Monday with no end',
            () async {
              await store.start(draftD);
              final review = reviewWeek(checkInPause);

              final written = await store.addWeek(
                1,
                monday: _firstMonday,
                inputs: checkInPause,
                review: review,
              );

              expect(review.rule, ReviewRule.pauseCheckIn);
              expect(review.pauseDays, isNull);
              expect(written, isTrue);
              expectPaused(await store.active(), since: _firstMonday);
            },
          );

          test('case 2: the pause leaves the block and the levers', () async {
            await store.start(draftD);

            await addRow(_firstMonday, checkInPause);

            final goal = (await store.active())!;
            expect(goal.blockStartedOn, _start);
            expect(goal.blockAnchorKg, 78.4);
            expectSameLevers(goal.levers, const [strengthLever]);
          });

          test('case 3: rule 4 twice in a row pauses for 14 days', () async {
            await store.start(draftD);
            final inputs = f1Recovering(recoveryPrevious: true);
            final review = reviewWeek(inputs);

            await addRow(_firstMonday, inputs);

            expect(review.rule, ReviewRule.recoveryWeek);
            expect(review.action, ReviewAction.pause);
            expect(review.pauseDays, 14);
            expectPaused(
              await store.active(),
              since: _firstMonday,
              until: const LocalDate(2026, 12, 20),
            );
          });

          test('case 3: a first recovery week leaves the goal as it '
              'was', () async {
            await store.start(draftD);
            final before = (await store.active())!;
            final inputs = f1Recovering(recoveryPrevious: false);
            final review = reviewWeek(inputs);

            await addRow(_firstMonday, inputs);

            expect(review.rule, ReviewRule.recoveryWeek);
            expect(review.action, ReviewAction.recoveryWeek);
            expect(review.pauseDays, isNull);
            expectSameGoal(await store.active(), before);
            expect(await store.weeks(1), hasLength(1));
          });

          test('a week that asks for nothing leaves the goal as it '
              'was', () async {
            await store.start(draftD);
            final before = (await store.active())!;

            await addRow(_firstMonday, f1);

            expectSameGoal(await store.active(), before);
          });

          test('case 4: rule 1 under the bmi floor ends the goal', () async {
            await store.start(draftD);
            final inputs = f1WithBmi(18);
            final review = reviewWeek(inputs);

            await addRow(_firstMonday, inputs);

            final goal = (await store.goals()).single;
            expect(review.rule, ReviewRule.end);
            expect(review.action, ReviewAction.end);
            expect(await store.active(), isNull);
            expect(goal.phase, GoalPhase.ended);
            expect(goal.endedOn, _firstMonday);
            expect(goal.endReason, GoalEndReason.protection);
          });

          test('case 4: the ended goal keeps its week', () async {
            await store.start(draftD);

            await addRow(_firstMonday, f1WithBmi(18));

            final weeks = await store.weeks(1);
            expect(weeks, hasLength(1));
            expect(weeks.single.rule, ReviewRule.end);
          });

          test('case 5: a refused addWeek leaves the goal as it '
              'was', () async {
            await store.start(draftD);
            await addRow(_firstMonday, f1);
            final before = (await store.active())!;

            final written = await store.addWeek(
              1,
              monday: _firstMonday,
              inputs: checkInPause,
              review: reviewWeek(checkInPause),
            );

            expect(written, isFalse);
            expectSameGoal(await store.active(), before);
          });

          test('case 5: a refused addWeek does not end a paused '
              'goal', () async {
            await store.start(draftD);
            await addRow(_firstMonday, checkInPause);

            final ending = f1WithBmi(18);
            final written = await store.addWeek(
              1,
              monday: _firstMonday,
              inputs: ending,
              review: reviewWeek(ending),
            );

            expect(written, isFalse);
            expectPaused(await store.active(), since: _firstMonday);
          });
        });

        group('G5b2b1 case 6: amendWeek applies a protection', () {
          test('rule 3 from the check-in pauses the goal', () async {
            await startWithPausableWeeks();
            expect((await store.active())!.phase, GoalPhase.block);

            await store.amendWeek(
              1,
              _firstMonday,
              energy: CheckInEnergy.low,
              foodOrWeight: null,
            );

            expectPaused(await store.active(), since: _firstMonday);
          });

          test('a refused amend leaves the paused goal as it was', () async {
            await startWithPausableWeeks();
            await store.amendWeek(
              1,
              _firstMonday,
              energy: CheckInEnergy.low,
              foodOrWeight: null,
            );
            final paused = (await store.active())!;

            final review = await store.amendWeek(
              1,
              _firstMonday,
              energy: CheckInEnergy.good,
              foodOrWeight: true,
            );

            expect(review, isNull);
            expectSameGoal(await store.active(), paused);
          });

          test('a rule 4 pause amended into rule 3 loses its end', () async {
            await store.start(draftD);
            await addRow(
              _firstMonday,
              f1Recovering(
                recoveryPrevious: true,
                energy: null,
                energyPrevious: CheckInEnergy.low,
                foodOrWeight: null,
              ),
            );
            expectPaused(
              await store.active(),
              since: _firstMonday,
              until: const LocalDate(2026, 12, 20),
            );

            final review = await store.amendWeek(
              1,
              _firstMonday,
              energy: CheckInEnergy.low,
              foodOrWeight: null,
            );

            expect(review?.rule, ReviewRule.pauseCheckIn);
            expectPaused(await store.active(), since: _firstMonday);
          });

          test('a week of an earlier block takes no check-in', () async {
            await store.start(draftD);
            await addRow(
              _firstMonday,
              f1Recovering(
                recoveryPrevious: true,
                energy: null,
                energyPrevious: CheckInEnergy.low,
                foodOrWeight: null,
              ),
            );
            await store.startBlock(
              1,
              on: const LocalDate(2026, 12, 21),
              anchorKg: null,
            );
            final before = (await store.weeks(1)).last;
            expect(before.rule, ReviewRule.recoveryWeek);
            expect(before.action, ReviewAction.pause);

            await expectUntouched(
              () => store.amendWeek(
                1,
                _firstMonday,
                energy: CheckInEnergy.low,
                foodOrWeight: null,
              ),
              before,
            );

            final goal = await store.active();
            expect(goal?.phase, GoalPhase.block);
            expect(goal?.phaseSince, const LocalDate(2026, 12, 21));
            expect(goal?.phaseUntil, isNull);
          });

          test('a week of an earlier block takes no answer', () async {
            await startWithBuildWeek();
            final levers = (await store.active())?.levers;
            await store.startBlock(
              1,
              on: const LocalDate(2026, 12, 21),
              anchorKg: null,
            );

            final answered = await store.answer(
              1,
              _firstMonday,
              WeekAnswer.accepted,
            );

            expect(answered, isFalse);
            expect((await store.weeks(1)).last.answer, isNull);
            expect(
              encodeLevers((await store.active())?.levers ?? const []),
              encodeLevers(levers ?? const []),
            );
          });

          test('a week on the first day of the block still amends', () async {
            await startWithBuildWeek();
            await store.startBlock(1, on: _firstMonday, anchorKg: null);

            final review = await store.amendWeek(
              1,
              _firstMonday,
              energy: CheckInEnergy.normal,
              foodOrWeight: null,
            );

            expect(review?.rule, ReviewRule.build);
          });
        });
      });
    });
  }
}
