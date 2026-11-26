import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/background/background_widget_publish.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/infrastructure/drift_weigh_in_store.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
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

  test(
    'a background sync publishes enabled module fields and respects hidden numbers',
    () async {
      final db = await pairedDatabase();
      final now = DateTime.utc(2026, 11, 10, 9);
      await DriftWeighInStore(db).add(
        WeighInDraft(
          at: now.subtract(const Duration(hours: 1)),
          offsetMinutes: 0,
          kilograms: 75.4,
        ),
      );
      final gateway = FakeWidgetGateway();

      await publishWidgetSnapshot(
        db,
        gateway,
        clock: () => now,
        modules: InMemoryModuleStore({ModuleId.body, ModuleId.effort}),
        hideNumbers: InMemoryHideNumbersStore(hidden: true),
      );

      final snapshot = gateway.snapshots.single;
      expect(snapshot['version'], 2);
      expect(snapshot['enabledModules'], containsAll(['body', 'effort']));
      expect(snapshot['hideNumbers'], isTrue);
      expect(snapshot['weight'], {
        'trendKilograms': null,
        'direction': 'building',
      });
      expect(snapshot['effort'], {
        'points': 0,
        'targetPoints': effortWeekPoints,
        'strengthDays': 0,
        'strengthTarget': effortWeekStrengthDays,
      });
    },
  );
}
