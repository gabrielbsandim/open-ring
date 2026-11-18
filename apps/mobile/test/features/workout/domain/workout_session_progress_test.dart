import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../../../helpers/workout_fakes.dart';

DateTime at(int seconds) => workoutStart.add(Duration(seconds: seconds));

WorkoutSession runFor(int seconds) {
  final session = WorkoutSession(
    type: WorkoutType.running,
    profile: const WorkoutProfile(weightKilograms: 70),
  )..start(workoutStart);
  for (var s = 0; s <= seconds; s++) {
    session
      ..addFix(fixAt(Duration(seconds: s), northMeters: s * 3.0))
      ..addHeartRate(130 + s, at(s));
  }
  return session;
}

void main() {
  test('progress of a running workout ends at the given instant and carries '
      'every sample', () {
    final session = runFor(10);

    final progress = session.progressAt(at(30));

    expect(progress.type, WorkoutType.running);
    expect(progress.start, workoutStart);
    expect(progress.end, at(30));
    expect(progress.elapsed, const Duration(seconds: 30));
    expect(progress.distanceMeters, closeTo(30, 1e-6));
    expect(progress.activeKilocalories, closeTo(8.8 * 70 * 30 / 3600, 1e-9));
    expect(progress.heartRate.map((s) => s.bpm), [
      for (var s = 0; s <= 10; s++) 130 + s,
    ]);
    expect(progress.averageHeartRate, 135);
    expect(progress.maxHeartRate, 140);
    expect(progress.route.points, hasLength(11));
    expect(progress.pauses, isEmpty);
  });

  test('progress of a paused workout ends at the pause and holds only the '
      'closed pauses', () {
    final session = runFor(10)
      ..pause(at(10))
      ..resume(at(20))
      ..pause(at(25));

    final progress = session.progressAt(at(90));

    expect(progress.end, at(25));
    expect(progress.elapsed, const Duration(seconds: 15));
    expect(progress.pauses.map((p) => (p.start, p.end)), [(at(10), at(20))]);
  });

  test('progress does not change the session', () {
    final session = runFor(10)..progressAt(at(100));

    expect(session.status, WorkoutStatus.running);
    expect(session.endedAt, isNull);
    expect(session.finished, throwsStateError);
    session.pause(at(50));
    expect(session.elapsedAt(at(200)), const Duration(seconds: 50));
  });

  test('a clock that stepped back does not end the progress before its last '
      'sample', () {
    final session = runFor(40);

    final progress = session.progressAt(at(20));

    expect(progress.end.isBefore(at(40)), isFalse);
    expect(progress.elapsed.isNegative, isFalse);
    expect(progress.heartRate, hasLength(41));
  });
}
