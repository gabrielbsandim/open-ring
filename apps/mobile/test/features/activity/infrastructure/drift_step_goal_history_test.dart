import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/domain/step_goal_history.dart';
import 'package:open_ring/features/activity/infrastructure/drift_step_goal_history.dart';

import '../../../helpers/database.dart';

const _dec7 = LocalDate(2026, 12, 7);
const _dec9 = LocalDate(2026, 12, 9);

void main() {
  final stores = <String, StepGoalHistory Function()>{
    'InMemoryStepGoalHistory': InMemoryStepGoalHistory.new,
    'DriftStepGoalHistory': () => DriftStepGoalHistory(memoryDatabase()),
  };

  for (final MapEntry(key: name, value: create) in stores.entries) {
    group(name, () {
      late StepGoalHistory store;

      setUp(() => store = create());

      test('changes is empty on a fresh store', () async {
        expect(await store.changes(), isEmpty);
      });

      test('the first record writes the baseline and the change', () async {
        await store.record(on: _dec7, steps: 10000, previous: 8000);

        expect(await store.changes(), [
          (from: stepGoalBaselineDate, steps: 8000),
          (from: _dec7, steps: 10000),
        ]);
      });

      test('a second record on the same day keeps one row', () async {
        await store.record(on: _dec7, steps: 10000, previous: 8000);

        await store.record(on: _dec7, steps: 9000, previous: 10000);

        expect(await store.changes(), [
          (from: stepGoalBaselineDate, steps: 8000),
          (from: _dec7, steps: 9000),
        ]);
      });

      test('a record on a later day adds a third row in order', () async {
        await store.record(on: _dec7, steps: 10000, previous: 8000);
        await store.record(on: _dec7, steps: 9000, previous: 10000);

        await store.record(on: _dec9, steps: 11000, previous: 9000);

        expect(await store.changes(), [
          (from: stepGoalBaselineDate, steps: 8000),
          (from: _dec7, steps: 9000),
          (from: _dec9, steps: 11000),
        ]);
      });

      test('the baseline is written once, from the first previous', () async {
        await store.record(on: _dec7, steps: 10000, previous: 8000);

        await store.record(on: _dec9, steps: 11000, previous: 5000);

        final changes = await store.changes();
        expect(changes.first, (from: stepGoalBaselineDate, steps: 8000));
        expect(changes, hasLength(3));
      });

      test('a record dated before the newest row replaces that row', () async {
        await store.record(on: _dec7, steps: 9000, previous: 8000);
        await store.record(on: _dec9, steps: 11000, previous: 9000);

        await store.record(on: _dec7, steps: 10000, previous: 11000);

        expect(await store.changes(), [
          (from: stepGoalBaselineDate, steps: 8000),
          (from: _dec7, steps: 9000),
          (from: _dec9, steps: 10000),
        ]);
      });
    });
  }

  group('DriftStepGoalHistory storage', () {
    test('rows land in step_goal_changes with the SQL values', () async {
      final db = memoryDatabase();

      await DriftStepGoalHistory(db)
          .record(on: _dec7, steps: 10000, previous: 8000);

      final rows = await db
          .customSelect(
            'SELECT effective_date, steps FROM step_goal_changes '
            'ORDER BY effective_date',
          )
          .get();
      expect(
        [
          for (final row in rows)
            (row.read<String>('effective_date'), row.read<int>('steps')),
        ],
        [('1970-01-01', 8000), ('2026-12-07', 10000)],
      );
    });

    test('a row whose date text is not a date is skipped', () async {
      final db = memoryDatabase();
      await db.customStatement(
        'INSERT INTO step_goal_changes (effective_date, steps) VALUES '
        "('not-a-date', 5000), ('2026-02-31', 6000), ('2026-12-07', 10000)",
      );

      expect(await DriftStepGoalHistory(db).changes(), [
        (from: _dec7, steps: 10000),
      ]);
    });

    test('a record over earlier rows does not add a baseline', () async {
      final db = memoryDatabase();
      await db.customStatement(
        'INSERT INTO step_goal_changes (effective_date, steps) '
        "VALUES ('2026-12-01', 9000)",
      );

      await DriftStepGoalHistory(db)
          .record(on: _dec7, steps: 10000, previous: 9000);

      expect(await rowCount(db, 'step_goal_changes'), 2);
    });
  });
}
