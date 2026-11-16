import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/infrastructure/drift_goal_store.dart';

import '../../../helpers/database.dart';
import '../goal_draft_fixture.dart';
import '../goal_fixtures.dart';

const _firstMonday = LocalDate(2026, 12, 7);

const _badWeek =
    'INSERT INTO goal_weeks (goal_id, monday, inputs, rule, action) '
    "VALUES (1, '2026-12-14', 'x', 'build', 'nextStep')";

const _badGoal =
    'INSERT INTO goals (kind, started_on, block_started_on, phase, '
    'phase_since, levers) '
    "VALUES ('loseFat', '2026-11-16', '2026-11-16', 'block', '2026-11-16', 'x')";

const _badScreening =
    "INSERT INTO goal_screenings (asked_on) VALUES ('not-a-date')";

void main() {
  late AppDatabase db;
  late DriftGoalStore store;

  setUp(() async {
    db = memoryDatabase();
    store = DriftGoalStore(db);
    await store.start(draftD);
    await store.addWeek(
      1,
      monday: _firstMonday,
      inputs: f1,
      review: reviewWeek(f1),
    );
    await db.customStatement(_badWeek);
  });

  group('criterion 20: a week row whose inputs do not decode', () {
    test('weeks skips it', () async {
      final weeks = await store.weeks(1);

      expect([for (final week in weeks) week.monday], [_firstMonday]);
    });

    test('count counts the raw rows', () async {
      expect(await store.count(), 3);
    });

    test('clear removes it and counts it as removed', () async {
      expect(await store.clear(), 3);

      expect(await rowCount(db, 'goal_weeks'), 0);
    });
  });

  group('criterion 20: a goal row whose levers do not decode', () {
    setUp(() async {
      await store.end(1, on: _firstMonday, reason: GoalEndReason.person);
      await db.customStatement(_badGoal);
    });

    test('goals skips it and keeps the readable goal', () async {
      final goals = await store.goals();

      expect([for (final goal in goals) goal.id], [1]);
    });

    test('active does not return it', () async {
      expect(await store.active(), isNull);
    });

    test('count counts it', () async {
      expect(await store.count(), 4);
    });
  });

  group('start', () {
    test('two starts at once leave one active goal', () async {
      await store.end(1, on: _firstMonday, reason: GoalEndReason.person);

      final started = await Future.wait([
        store.start(draftD),
        store.start(draftD),
      ]);

      expect(started.where((goal) => goal != null), hasLength(1));
      expect(await rowCount(db, 'goals'), 2);
    });

    test('an open goal that decodes still refuses a second one', () async {
      await db.customStatement(_badGoal);

      expect(await store.start(draftD), isNull);
      expect((await store.active())!.id, 1);
    });

    test('an open goal that does not decode is ended and the new one '
        'starts', () async {
      await store.end(1, on: _firstMonday, reason: GoalEndReason.person);
      await db.customStatement(_badGoal);

      final started = await store.start(draftD);

      final bad = await db
          .customSelect(
            'SELECT phase, ended_on, end_reason FROM goals WHERE id = 2',
          )
          .getSingle();
      expect(started!.id, 3);
      expect((await store.active())!.id, 3);
      expect(bad.read<String>('phase'), 'ended');
      expect(bad.read<String>('ended_on'), '2026-11-16');
      expect(bad.read<String>('end_reason'), 'unreadable');
    });

    test('the ended unreadable goal keeps its weeks', () async {
      await db.customStatement("UPDATE goals SET levers = 'x' WHERE id = 1");

      await store.start(draftD);

      expect(await rowCount(db, 'goal_weeks'), 2);
      expect((await store.active())!.id, 2);
    });
  });

  group('criterion 20: a screening row whose date does not parse', () {
    setUp(() => db.customStatement(_badScreening));

    test('screenings skips it', () async {
      expect(await store.screenings(), isEmpty);
    });

    test('count counts it', () async {
      expect(await store.count(), 4);
    });
  });

  group('criterion 20: clear', () {
    setUp(() async {
      await store.addScreening(
        const GoalScreening(
          on: _firstMonday,
          softMode: false,
          pregnantOrBreastfeeding: null,
        ),
      );
    });

    test('returns every row once, cascade included', () async {
      expect(await store.clear(), 4);
    });

    test('leaves the three tables empty', () async {
      await store.clear();

      expect(await rowCount(db, 'goals'), 0);
      expect(await rowCount(db, 'goal_weeks'), 0);
      expect(await rowCount(db, 'goal_screenings'), 0);
    });
  });

  group('the week rows follow their goal', () {
    test('deleting the goal row removes its weeks', () async {
      await db.customStatement('DELETE FROM goals WHERE id = 1');

      expect(await rowCount(db, 'goal_weeks'), 0);
    });

    test('a week for a goal that does not exist is refused', () async {
      final insert = db.customStatement(
        'INSERT INTO goal_weeks (goal_id, monday, inputs, rule, action) '
        "VALUES (99, '2026-12-07', 'x', 'build', 'nextStep')",
      );

      await expectLater(insert, throwsA(anything));
    });
  });
}
