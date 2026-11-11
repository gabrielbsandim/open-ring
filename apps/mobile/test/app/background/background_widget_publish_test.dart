import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/background/background_widget_publish.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_store.dart';

import '../../helpers/database.dart';
import '../../helpers/widget_fakes.dart';

void main() {
  test(
    'a background sync publishes the snapshot read from the database',
    () async {
      final db = await pairedDatabase();
      final gateway = FakeWidgetGateway();

      await publishWidgetSnapshot(
        db,
        gateway,
        clock: () => DateTime.utc(2026, 11, 10, 9),
      );

      final snapshot = gateway.snapshots.single;
      expect(snapshot['paired'], isTrue);
      expect(snapshot['date'], '2026-11-10');
      expect(snapshot['syncedAtMs'], isNull);
      expect(snapshot['steps'], isNull);
      expect(snapshot['stepGoal'], 8000);
      expect(gateway.appearances, isEmpty);
    },
  );

  test('an empty database publishes an unpaired snapshot', () async {
    final gateway = FakeWidgetGateway();

    await publishWidgetSnapshot(memoryDatabase(), gateway);

    expect(gateway.snapshots.single['paired'], isFalse);
  });

  test('a background sync publishes the last saved workout', () async {
    final db = await pairedDatabase();
    final start = DateTime.utc(2026, 11, 9, 18);
    final walk =
        (WorkoutSession(type: WorkoutType.walking, gps: false)
              ..start(start)
              ..finish(start.add(const Duration(minutes: 32))))
            .finished();
    await DriftWorkoutStore(db).save(walk, at: walk.end);
    final gateway = FakeWidgetGateway();

    await publishWidgetSnapshot(
      db,
      gateway,
      clock: () => DateTime.utc(2026, 11, 10, 9),
    );

    expect(gateway.snapshots.single['lastWorkout'], {
      'type': 'walking',
      'startMs': start.millisecondsSinceEpoch,
      'elapsedSeconds': 1920,
      'distanceMeters': null,
    });
  });
}
