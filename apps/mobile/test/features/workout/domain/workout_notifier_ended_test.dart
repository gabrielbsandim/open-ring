import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';

void main() {
  const saved = WorkoutEndNotice(
    title: 'Workout saved',
    text: 'Running · 40:00 · 6.60 km · Avg HR 146',
    action: 'See workout summary',
    link: 'openring://widget/activity/workout-summary/42',
  );
  const failed = WorkoutEndNotice(
    title: 'The workout was not saved',
    text: 'Open the app to try again. Closing it loses the workout.',
    action: 'Open',
    link: 'openring://widget/activity/workout-summary',
  );

  test('the channel defaults to the live channel name', () {
    expect(saved.channel, 'Workout');
    expect(saved.channel, const WorkoutNoticeLabels().channel);
  });

  group('the in-memory notifier', () {
    test('records each ended notice in order and each clear', () async {
      final notifier = InMemoryWorkoutNotifier();

      await notifier.ended(failed);
      await notifier.clearEnded();
      await notifier.ended(saved);

      expect(notifier.endedNotices, [failed, saved]);
      expect(notifier.endedClears, 1);
    });

    test('starts with nothing ended and nothing cleared', () {
      final notifier = InMemoryWorkoutNotifier();

      expect(notifier.endedNotices, isEmpty);
      expect(notifier.endedClears, 0);
    });

    test('5: fails on ended when failing is set', () async {
      final notifier = InMemoryWorkoutNotifier()..failing = true;

      await expectLater(
        notifier.ended(saved),
        throwsA(isA<WorkoutNotifierFailure>()),
      );
      expect(notifier.endedNotices, isEmpty);
    });

    test('5: fails on clearEnded when failing is set', () async {
      final notifier = InMemoryWorkoutNotifier()..failing = true;

      await expectLater(
        notifier.clearEnded(),
        throwsA(isA<WorkoutNotifierFailure>()),
      );
      expect(notifier.endedClears, 0);
    });
  });
}
