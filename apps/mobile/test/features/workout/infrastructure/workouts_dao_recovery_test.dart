import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/workout/infrastructure/workouts_dao.dart';

import '../../../helpers/database.dart';
import '../../../helpers/open_workout_fakes.dart';

void main() {
  late AppDatabase db;
  late WorkoutsDao dao;

  setUp(() {
    db = memoryDatabase();
    dao = WorkoutsDao(db);
  });

  test('openStarts lists only the rows with no end, oldest first', () async {
    await insertOpenRow(db, start: openStartAfter(2));
    await insertFinishedRow(db, start: openStartAfter(1));
    await insertOpenRow(db);

    expect(await dao.openStarts(), [openStart, openStartAfter(2)]);
  });

  test('openStarts is empty with no open row', () async {
    await insertFinishedRow(db, start: openStart);

    expect(await dao.openStarts(), isEmpty);
  });

  test('closeOpen ends the row at its checkpoint and keeps the elapsed time '
      'and the checkpoint', () async {
    final id = await insertOpenRow(
      db,
      checkpoint: DateTime.utc(2026, 11, 10, 7, 31),
    );

    final closed = await dao.closeOpen(openStart);

    expect(closed!.id, id);
    final row = await rowOf(db, id);
    expect(row.endUtcMs, DateTime.utc(2026, 11, 10, 7, 31).utcMs);
    expect(row.checkpointUtcMs, DateTime.utc(2026, 11, 10, 7, 31).utcMs);
    expect(row.elapsedMs, 21 * 60 * 1000);
  });

  test(
    'closeOpen ends at start plus elapsed when the checkpoint is null',
    () async {
      final id = await insertOpenRow(
        db,
        elapsed: const Duration(minutes: 12),
        withCheckpoint: false,
      );

      await dao.closeOpen(openStart);

      final row = await rowOf(db, id);
      expect(row.endUtcMs, openStart.add(const Duration(minutes: 12)).utcMs);
      expect(row.checkpointUtcMs, isNull);
    },
  );

  test('closeOpen leaves a row that already has an end untouched', () async {
    final id = await insertFinishedRow(db, start: openStart);
    final before = await rowOf(db, id);

    expect(await dao.closeOpen(openStart), isNull);

    expect(await rowOf(db, id), before);
  });

  test('closeOpen on a start with no row returns null', () async {
    expect(await dao.closeOpen(openStart), isNull);
    expect(await rowCount(db, 'workouts'), 0);
  });

  test('closing twice changes the row once', () async {
    final id = await insertOpenRow(db);
    await dao.closeOpen(openStart);
    final first = await rowOf(db, id);

    expect(await dao.closeOpen(openStart), isNull);

    expect(await rowOf(db, id), first);
  });
}
