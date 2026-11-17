import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_records.dart';
import 'package:open_ring/features/export/infrastructure/export_pages_dao.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_health_record_source.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_history_reader.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_rating_store.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_store.dart';

import '../../../helpers/database.dart';
import '../../../helpers/workout_fakes.dart';

const openAfter = Duration(hours: 2);

final DateTime from = workoutStart.subtract(const Duration(hours: 1));
final DateTime to = workoutStart.add(const Duration(hours: 4));

WorkoutSession runFrom(Duration startAfter, {required int seconds}) {
  final start = workoutStart.add(startAfter);
  final session = WorkoutSession(
    type: WorkoutType.running,
    profile: const WorkoutProfile(weightKilograms: 70),
  )..start(start);
  for (var s = 0; s <= seconds; s++) {
    session
      ..addFix(fixAt(startAfter + Duration(seconds: s), northMeters: s * 3.0))
      ..addHeartRate(130 + s % 20, start.add(Duration(seconds: s)));
  }
  return session;
}

void main() {
  late AppDatabase db;
  late int finishedId;
  late int openId;

  setUp(() async {
    db = memoryDatabase();
    final store = DriftWorkoutStore(db);
    final done = runFrom(Duration.zero, seconds: 80)
      ..finish(workoutStart.add(const Duration(seconds: 80)));
    finishedId = await store.save(
      done.finished(),
      at: workoutStart.add(const Duration(seconds: 81)),
    );
    await store.checkpoint(
      runFrom(openAfter, seconds: 60),
      at: workoutStart.add(openAfter + const Duration(seconds: 60)),
    );
    final open = await (db.select(
      db.workouts,
    )..where((w) => w.endUtcMs.isNull())).getSingle();
    openId = open.id;
  });

  test('the fixture holds one open and one finished row', () async {
    expect(await rowCount(db, 'workouts'), 2);
    expect(openId, isNot(finishedId));
  });

  test('recent returns only the finished row', () async {
    final items = await DriftWorkoutHistoryReader(db).recent(limit: 10);

    expect(items.map((i) => i.id), [finishedId]);
  });

  test('intersecting returns only the finished row', () async {
    final items = await DriftWorkoutHistoryReader(db)
        .intersecting(from: from, to: to);

    expect(items.map((i) => i.id), [finishedId]);
  });

  test('byId of the open row returns nothing', () async {
    expect(await DriftWorkoutHistoryReader(db).byId(openId), isNull);
    expect(await DriftWorkoutHistoryReader(db).byId(finishedId), isNotNull);
  });

  test('routed returns only the finished row', () async {
    final routed = await DriftWorkoutHistoryReader(db)
        .routed(from: from, to: to, types: {WorkoutType.running});

    expect(routed.map((w) => w.id), [finishedId]);
  });

  test(
    'the health source workout batch carries only the finished row',
    () async {
      final outbox = HealthOutboxDao(db);
      await outbox.enqueueWorkout(start: from, end: to, at: to);
      final entry = (await outbox.due(to)).singleWhere(
        (e) => e.from.utcMs == from.utcMs && e.to.utcMs == to.utcMs,
      );

      final batches = await DriftHealthRecordSource(db)
          .batches(entry, batchSize: 200);

      final written = [
        for (final batch in batches) ...batch.entries.cast<WorkoutEntry>(),
      ];
      expect(written.map((w) => w.start.utcMs), [workoutStart.utcMs]);
    },
  );

  test('the workouts export carries only the finished row', () async {
    final pages = await ExportPagesDao(db)
        .pages(ExportKind.workouts, from: from, to: to)
        .toList();

    expect(
      [
        for (final page in pages)
          for (final record in page.cast<WorkoutRecord>()) record.clientId,
      ],
      ['phone:${workoutStart.utcMs}'],
    );
  });

  test('an open row adds nothing to the rating count', () async {
    final ratings = DriftWorkoutRatingStore(db);
    await ratings.rateRecorded(finishedId, 6);

    expect(await ratings.countRatings(), 1);
  });
}
