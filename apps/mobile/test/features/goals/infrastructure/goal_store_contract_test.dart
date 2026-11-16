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

void expectSameGoal(Goal? actual, Goal expected) {
  expect(actual, isNotNull);
  final goal = actual!;
  expect(goal.id, expected.id);
  expect(goal.kind, expected.kind);
  expect(goal.pace, expected.pace);
  expect(goal.startedOn, expected.startedOn);
  expect(goal.anchorKg, expected.anchorKg);
  expect(goal.referenceKg, expected.referenceKg);
  expect(goal.blockStartedOn, expected.blockStartedOn);
  expect(goal.blockAnchorKg, expected.blockAnchorKg);
  expect(goal.phase, expected.phase);
  expect(goal.phaseSince, expected.phaseSince);
  expect(goal.phaseUntil, expected.phaseUntil);
  expectSameLevers(goal.levers, expected.levers);
  expect(goal.endedOn, expected.endedOn);
  expect(goal.endReason, expected.endReason);
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
    });
  }
}
