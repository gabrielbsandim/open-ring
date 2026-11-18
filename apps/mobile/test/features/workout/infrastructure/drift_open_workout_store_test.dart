import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/demo/domain/demo_data.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/infrastructure/drift_open_workout_store.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_history_reader.dart';

import '../../../helpers/database.dart';
import '../../../helpers/open_workout_fakes.dart';

final checkpointAt = DateTime.utc(2026, 11, 10, 7, 31);
final launchAt = DateTime.utc(2026, 11, 10, 12);

void main() {
  late AppDatabase db;
  late DriftOpenWorkoutStore store;

  setUp(() {
    db = memoryDatabase();
    store = DriftOpenWorkoutStore(db);
  });

  test('criterion 1: an open row checkpointed at 07:31 with 21:00 elapsed '
      'ends there, queues one outbox row and shows in recent', () async {
    final id = await insertOpenRow(db, checkpoint: checkpointAt);

    final recovered = await store.close(openStart, at: launchAt);

    final row = await rowOf(db, id);
    expect(row.endUtcMs, checkpointAt.utcMs);
    expect(row.elapsedMs, 21 * 60 * 1000);
    expect(row.checkpointUtcMs, isNull);
    final outbox = await HealthOutboxDao(db).all();
    expect(outbox.map((r) => (r.kind, r.fromUtcMs, r.toUtcMs)), [
      (HealthRecordKind.workout, openStart.utcMs, checkpointAt.utcMs),
    ]);
    expect(recovered!.id, id);
    expect(recovered.type, WorkoutType.running);
    expect(recovered.start, openStart);
    expect(recovered.end, checkpointAt);
    expect(recovered.elapsed, const Duration(minutes: 21));
    expect(recovered.distanceMeters, 3000);
    expect(recovered.offsetMinutes, 0);
    final recent = await DriftWorkoutHistoryReader(db).recent(limit: 5);
    expect(recent.map((item) => item.id), [id]);
  });

  test('the recovered offset is the one stored on the row', () async {
    await insertOpenRow(db, offsetMinutes: -180);

    final recovered = await store.close(openStart, at: launchAt);

    expect(recovered!.offsetMinutes, -180);
  });

  test('criterion 2: a demo open row closes with no outbox row', () async {
    final id = await insertOpenRow(db, deviceId: demoDeviceId);

    final recovered = await store.close(openStart, at: launchAt);

    expect((await rowOf(db, id)).endUtcMs, isNotNull);
    expect(recovered!.id, id);
    expect(await rowCount(db, 'health_outbox'), 0);
  });

  test('closing a row that is already finished returns null and queues '
      'nothing', () async {
    final id = await insertFinishedRow(db, start: openStart);
    final before = await rowOf(db, id);

    expect(await store.close(openStart, at: launchAt), isNull);

    expect(await rowOf(db, id), before);
    expect(await rowCount(db, 'health_outbox'), 0);
  });

  test('openStarts lists the open rows', () async {
    await insertOpenRow(db);
    await insertFinishedRow(db, start: openStartAfter(3));

    expect(await store.openStarts(), [openStart]);
  });
}
