import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_recovery.dart';
import 'package:open_ring/features/workout/application/workout_state.dart';
import 'package:open_ring/features/workout/domain/workout_recovery.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../../../helpers/workout_fakes.dart';

void main() {
  late InMemoryLiveWorkoutRegistry registry;

  setUp(() => registry = InMemoryLiveWorkoutRegistry());

  ProviderContainer container(WorkoutRig rig) {
    final container = ProviderContainer(
      overrides: [
        ...rig.overrides(),
        liveWorkoutRegistryProvider.overrideWithValue(registry),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(rig.ticks.close);
    return container;
  }

  Future<WorkoutController> started(ProviderContainer c) async {
    final controller = c.read(workoutProvider.notifier);
    await controller.start(WorkoutType.running, notice: testNotice);
    return controller;
  }

  test(
    'criterion 8: the start is marked live while the workout runs',
    () async {
      final c = container(WorkoutRig());
      expect(registry.isLive(workoutStart), isFalse);

      await started(c);

      expect(registry.isLive(workoutStart), isTrue);
    },
  );

  test('criterion 8: the mark is cleared after a successful save', () async {
    final rig = WorkoutRig();
    final c = container(rig);
    final controller = await started(c);
    rig.run(5);

    await controller.finish();

    expect(c.read(workoutProvider).save, WorkoutSave.saved);
    expect(registry.isLive(workoutStart), isFalse);
  });

  test('criterion 8: the mark is cleared after a discard', () async {
    final rig = WorkoutRig();
    final c = container(rig);
    final controller = await started(c);
    rig.run(5);

    await controller.discard();

    expect(registry.isLive(workoutStart), isFalse);
  });

  test('criterion 8: the mark stays after a failed save', () async {
    final rig = WorkoutRig(store: FlakyWorkoutStore(RecordingWorkoutStore()));
    final c = container(rig);
    final controller = await started(c);
    rig.run(5);

    await controller.finish();

    expect(c.read(workoutProvider).save, WorkoutSave.failed);
    expect(registry.isLive(workoutStart), isTrue);
  });

  test(
    'criterion 8: a save that succeeds on the retry clears the mark',
    () async {
      final rig = WorkoutRig(store: FlakyWorkoutStore(RecordingWorkoutStore()));
      final c = container(rig);
      final controller = await started(c);
      rig.run(5);
      await controller.finish();

      await controller.saveAgain();

      expect(c.read(workoutProvider).save, WorkoutSave.saved);
      expect(registry.isLive(workoutStart), isFalse);
    },
  );

  test('criterion 8: disposing the controller clears the mark', () async {
    final rig = WorkoutRig();
    final c = container(rig);
    await started(c);
    expect(registry.isLive(workoutStart), isTrue);

    c.dispose();

    expect(registry.isLive(workoutStart), isFalse);
  });
}
