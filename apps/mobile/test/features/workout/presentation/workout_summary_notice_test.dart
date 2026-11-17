import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';
import 'package:open_ring/features/workout/presentation/workout_summary_screen.dart';

import '../../../helpers/workout_fakes.dart';
import 'workout_scenarios.dart';

const _savedId = 42;

final class _NotifierRig extends WorkoutRig {
  new(this.notifier, {super.store});

  final InMemoryWorkoutNotifier notifier;

  @override
  List<Override> overrides() => [
    ...super.overrides(),
    workoutNotifierProvider.overrideWithValue(notifier),
  ];
}

void main() {
  late InMemoryWorkoutNotifier notifier;

  setUp(() => notifier = InMemoryWorkoutNotifier());

  _NotifierRig savedRig() => _NotifierRig(
    notifier,
    store: MemoryWorkoutHistory(seed: [savedRun(id: _savedId)]),
  );

  group('6: opening the summary clears the ended notice', () {
    testWidgets('WorkoutSummaryScreen(workoutId: 42) clears once', (
      tester,
    ) async {
      await pumpWorkout(
        tester,
        const WorkoutSummaryScreen(workoutId: _savedId),
        savedRig(),
        size: tallPhone,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(WorkoutSummaryKeys.duration), findsWidgets);
      expect(notifier.endedClears, 1);
    });

    testWidgets('a rebuild does not clear again', (tester) async {
      await pumpWorkout(
        tester,
        const WorkoutSummaryScreen(workoutId: _savedId),
        savedRig(),
        size: tallPhone,
      );
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(notifier.endedClears, 1);
    });

    testWidgets('the failed link with no session shows none and clears', (
      tester,
    ) async {
      await pumpWorkout(
        tester,
        const WorkoutSummaryScreen(),
        _NotifierRig(notifier),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(WorkoutSummaryKeys.none), findsOneWidget);
      expect(notifier.endedClears, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failing notifier still shows the summary', (tester) async {
      notifier.failing = true;
      await pumpWorkout(
        tester,
        const WorkoutSummaryScreen(workoutId: _savedId),
        savedRig(),
        size: tallPhone,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(WorkoutSummaryKeys.duration), findsWidgets);
      expect(notifier.endedClears, 0);
    });
  });
}
