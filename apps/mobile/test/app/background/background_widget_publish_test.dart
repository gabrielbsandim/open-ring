import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/background/background_widget_publish.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/infrastructure/drift_weigh_in_store.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/infrastructure/drift_goal_store.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/settings/infrastructure/drift_user_profile_store.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_store.dart';

import '../../helpers/database.dart';
import '../../helpers/widget_fakes.dart';

final class _FailingModuleStore implements ModuleStore {
  @override
  Future<Set<ModuleId>> read() => Future.error(StateError('prefs failed'));

  @override
  Future<void> write(Set<ModuleId> enabled) async {}

  @override
  Future<bool> shortcutDismissed() async => false;

  @override
  Future<void> dismissShortcut({required bool dismissed}) async {}
}

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

  test('a background sync publishes enabled module fields and respects hidden numbers', () async {
    final db = await pairedDatabase();
    final now = DateTime.utc(2026, 11, 10, 12);
    await DriftUserProfileStore(db).save(
      const UserProfile(
        birthYear: 1992,
        sex: Sex.female,
        heightCentimeters: 170,
        weightKilograms: 75,
        dailyStepGoal: 8000,
      ),
      at: now,
    );
    await DriftWeighInStore(db).add(
      WeighInDraft(
        at: now.subtract(const Duration(hours: 1)),
        offsetMinutes: 0,
        kilograms: 75.4,
      ),
    );
    await DriftGoalStore(db).start(
      const GoalDraft(
        kind: GoalKind.getFitter,
        pace: null,
        startedOn: LocalDate(2026, 11, 2),
        anchorKg: null,
        referenceKg: null,
        levers: [Lever(kind: LeverKind.strengthDays, target: 2)],
      ),
    );
    const modules = {
      ModuleId.body,
      ModuleId.openScore,
      ModuleId.energy,
      ModuleId.effort,
      ModuleId.goals,
    };
    final visibleGateway = FakeWidgetGateway();
    await publishWidgetSnapshot(
      db,
      visibleGateway,
      clock: () => now,
      modules: InMemoryModuleStore(modules),
      hideNumbers: InMemoryHideNumbersStore(),
    );

    final visible = visibleGateway.snapshots.single;
    expect(visible['version'], 2);
    expect(visible['enabledModules'], [
      'body',
      'effort',
      'energy',
      'goals',
      'openScore',
    ]);
    expect(visible['hideNumbers'], isFalse);
    expect(visible['weight'], {
      'trendKilograms': 75.4,
      'direction': 'building',
    });
    expect(visible['energy'], isNotNull);
    expect(visible['dayScore'], isNotNull);
    expect(visible['goals'], isNotNull);
    expect(visible['effort'], {
      'points': 0,
      'targetPoints': effortWeekPoints,
      'strengthDays': 0,
      'strengthTarget': effortWeekStrengthDays,
    });

    final hiddenGateway = FakeWidgetGateway();
    await publishWidgetSnapshot(
      db,
      hiddenGateway,
      clock: () => now,
      modules: InMemoryModuleStore({ModuleId.body, ModuleId.energy}),
      hideNumbers: InMemoryHideNumbersStore(hidden: true),
    );

    final hidden = hiddenGateway.snapshots.single;
    expect(hidden['enabledModules'], ['body', 'energy']);
    expect(hidden['hideNumbers'], isTrue);
    expect(hidden['weight'], {'trendKilograms': null, 'direction': 'building'});
    expect(hidden['energy'], isNull);
    expect(hidden['dayScore'], isNull);
    expect(hidden['effort'], isNull);
    expect(hidden['goals'], isNull);
  });

  test(
    'a failing module store still publishes the base ring snapshot',
    () async {
      final db = await pairedDatabase();
      final gateway = FakeWidgetGateway();

      await publishWidgetSnapshot(
        db,
        gateway,
        clock: () => DateTime.utc(2026, 11, 10, 9),
        modules: _FailingModuleStore(),
      );

      final snapshot = gateway.snapshots.single;
      expect(snapshot['paired'], isTrue);
      expect(snapshot['enabledModules'], isEmpty);
      expect(snapshot['dayScore'], isNull);
    },
  );
}
