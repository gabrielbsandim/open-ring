import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';

void main() {
  const notice = WorkoutNotice(
    title: 'Running',
    text: '148 bpm',
    elapsed: Duration(seconds: 5),
    running: true,
  );

  test('notices with the same four fields are equal', () {
    const same = WorkoutNotice(
      title: 'Running',
      text: '148 bpm',
      elapsed: Duration(seconds: 5),
      running: true,
    );

    expect(same, notice);
    expect(same.hashCode, notice.hashCode);
  });

  test('a notice differs when any one field differs', () {
    final others = [
      const WorkoutNotice(
        title: 'Walking',
        text: '148 bpm',
        elapsed: Duration(seconds: 5),
        running: true,
      ),
      const WorkoutNotice(
        title: 'Running',
        text: '149 bpm',
        elapsed: Duration(seconds: 5),
        running: true,
      ),
      const WorkoutNotice(
        title: 'Running',
        text: '148 bpm',
        elapsed: Duration(seconds: 6),
        running: true,
      ),
      const WorkoutNotice(
        title: 'Running',
        text: '148 bpm',
        elapsed: Duration(seconds: 5),
        running: false,
      ),
    ];

    for (final other in others) {
      expect(other, isNot(notice));
    }
  });

  test('the in-memory notifier records shows, hides and taps', () async {
    final notifier = InMemoryWorkoutNotifier();
    final received = <WorkoutNoticeAction>[];
    final sub = notifier.actions.listen(received.add);

    await notifier.show(notice);
    await notifier.hide();
    notifier
      ..tap(WorkoutNoticeAction.pause)
      ..tap(WorkoutNoticeAction.stop);
    await pumpEventQueue();
    await sub.cancel();

    expect(notifier.shown, [notice]);
    expect(notifier.hides, 1);
    expect(received, [WorkoutNoticeAction.pause, WorkoutNoticeAction.stop]);
  });

  test('a failing in-memory notifier throws', () async {
    final notifier = InMemoryWorkoutNotifier()..failing = true;

    await expectLater(
      notifier.show(notice),
      throwsA(isA<WorkoutNotifierFailure>()),
    );
    await expectLater(notifier.hide(), throwsA(isA<WorkoutNotifierFailure>()));
    expect(notifier.shown, isEmpty);
    expect(notifier.hides, 0);
  });

  test('the action enum has pause, resume and stop', () {
    expect(WorkoutNoticeAction.values, [
      WorkoutNoticeAction.pause,
      WorkoutNoticeAction.resume,
      WorkoutNoticeAction.stop,
    ]);
  });
}
